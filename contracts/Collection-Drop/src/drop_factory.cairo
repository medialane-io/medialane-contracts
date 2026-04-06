/// DropFactory — Multi-tenant factory for Collection Drop instances.
///
/// Any address granted ORGANIZER_ROLE can deploy their own limited-edition
/// timed NFT drop. The factory:
///   - Registers and revokes organizers
///   - Deploys independent DropCollection contracts per drop
///   - Passes platform_admin to each collection for emergency override
///   - Maintains a per-organizer drop index for on-chain discovery

#[starknet::contract]
pub mod DropFactory {
    use core::num::traits::Zero;
    use openzeppelin_access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_upgrades::UpgradeableComponent;
    use openzeppelin_upgrades::interface::IUpgradeable;
    use starknet::{ClassHash, ContractAddress, get_caller_address, get_block_timestamp};
    use starknet::syscalls::deploy_syscall;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StoragePathEntry,
    };

    use crate::interfaces::IDropFactory::IDropFactory;
    use crate::events::{DropCreated, OrganizerRegistered, OrganizerRevoked};
    use crate::types::{ClaimConditions, DropRecord, OrganizerRecord};

    /// Role for addresses authorised to create drop collections.
    pub const ORGANIZER_ROLE: felt252 = selector!("ORGANIZER_ROLE");

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl AccessControlMixinImpl =
        AccessControlComponent::AccessControlMixinImpl<ContractState>;

    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        /// The Medialane platform admin address, passed to every deployed collection.
        platform_admin: ContractAddress,
        /// Class hash of DropCollection used for each deploy_syscall.
        drop_collection_class_hash: ClassHash,
        /// Auto-incrementing drop counter.
        last_drop_id: u256,
        /// drop_id → DropRecord
        drops: Map<u256, DropRecord>,
        /// organizer_address → OrganizerRecord
        organizers: Map<ContractAddress, OrganizerRecord>,
        /// organizer → number of drops they have created
        organizer_drop_count: Map<ContractAddress, u32>,
        /// (organizer, index) → drop_id
        organizer_drops: Map<(ContractAddress, u32), u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        DropCreated: DropCreated,
        OrganizerRegistered: OrganizerRegistered,
        OrganizerRevoked: OrganizerRevoked,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        drop_collection_class_hash: ClassHash,
    ) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, admin);
        // Admin can also create drops directly
        self.accesscontrol._grant_role(ORGANIZER_ROLE, admin);
        self.platform_admin.write(admin);
        self.drop_collection_class_hash.write(drop_collection_class_hash);
    }

    #[abi(embed_v0)]
    impl DropFactoryImpl of IDropFactory<ContractState> {
        // ── Organizer management ─────────────────────────────────────────────

        fn register_organizer(
            ref self: ContractState, organizer: ContractAddress, name: ByteArray,
        ) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            assert(!organizer.is_zero(), 'Invalid organizer address');
            assert(name.len() > 0, 'Name cannot be empty');

            self.accesscontrol._grant_role(ORGANIZER_ROLE, organizer);
            self
                .organizers
                .entry(organizer)
                .write(OrganizerRecord { name: name.clone(), active: true, registered_at: get_block_timestamp() });

            self.emit(OrganizerRegistered { organizer, name, timestamp: get_block_timestamp() });
        }

        fn revoke_organizer(ref self: ContractState, organizer: ContractAddress) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            assert(!organizer.is_zero(), 'Invalid organizer address');

            self.accesscontrol._revoke_role(ORGANIZER_ROLE, organizer);

            let mut record = self.organizers.entry(organizer).read();
            record.active = false;
            self.organizers.entry(organizer).write(record);

            self.emit(OrganizerRevoked { organizer, timestamp: get_block_timestamp() });
        }

        fn get_organizer(self: @ContractState, organizer: ContractAddress) -> OrganizerRecord {
            self.organizers.entry(organizer).read()
        }

        fn is_active_organizer(self: @ContractState, organizer: ContractAddress) -> bool {
            self.organizers.entry(organizer).read().active
        }

        // ── Drop management ──────────────────────────────────────────────────

        fn create_drop(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            base_uri: ByteArray,
            max_supply: u256,
            initial_conditions: ClaimConditions,
        ) -> ContractAddress {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            assert(name.len() > 0, 'Drop name cannot be empty');
            // If paid drop, payment token must be specified
            if initial_conditions.price > 0 {
                assert(
                    !initial_conditions.payment_token.is_zero(), 'Payment token required',
                );
            }

            let organizer = get_caller_address();
            let platform_admin = self.platform_admin.read();
            let next_id = self.last_drop_id.read() + 1;
            let timestamp = get_block_timestamp();

            // Serialize constructor args — order must match DropCollection constructor.
            let mut calldata: Array<felt252> = array![];
            (
                name.clone(),
                symbol.clone(),
                base_uri,
                next_id,
                max_supply,
                platform_admin,
                organizer,
                initial_conditions.clone(),
            )
                .serialize(ref calldata);

            let (collection_address, _) = deploy_syscall(
                self.drop_collection_class_hash.read(),
                next_id.try_into().unwrap(), // deterministic salt
                calldata.span(),
                false,
            )
                .unwrap();

            self
                .drops
                .entry(next_id)
                .write(
                    DropRecord {
                        drop_id: next_id,
                        name: name.clone(),
                        symbol: symbol.clone(),
                        organizer,
                        collection_address,
                        max_supply,
                        created_at: timestamp,
                    },
                );
            self.last_drop_id.write(next_id);

            // Update organizer→drops index
            let od_index = self.organizer_drop_count.entry(organizer).read();
            self.organizer_drops.entry((organizer, od_index)).write(next_id);
            self.organizer_drop_count.entry(organizer).write(od_index + 1);

            self
                .emit(
                    DropCreated {
                        drop_id: next_id,
                        organizer,
                        collection_address,
                        name,
                        max_supply,
                        timestamp,
                    },
                );

            collection_address
        }

        fn get_drop(self: @ContractState, drop_id: u256) -> DropRecord {
            self.drops.entry(drop_id).read()
        }

        fn get_drop_address(self: @ContractState, drop_id: u256) -> ContractAddress {
            self.drops.entry(drop_id).read().collection_address
        }

        fn get_last_drop_id(self: @ContractState) -> u256 {
            self.last_drop_id.read()
        }

        fn get_organizer_drop_count(self: @ContractState, organizer: ContractAddress) -> u32 {
            self.organizer_drop_count.entry(organizer).read()
        }

        fn get_organizer_drop_ids(
            self: @ContractState, organizer: ContractAddress, start: u32, count: u32,
        ) -> Array<u256> {
            let total = self.organizer_drop_count.entry(organizer).read();
            let mut result: Array<u256> = array![];
            let end = start + count;
            let mut i = start;
            loop {
                if i >= end || i >= total {
                    break;
                }
                result.append(self.organizer_drops.entry((organizer, i)).read());
                i += 1;
            };
            result
        }

        fn get_drop_collection_class_hash(self: @ContractState) -> ClassHash {
            self.drop_collection_class_hash.read()
        }

        fn set_drop_collection_class_hash(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.drop_collection_class_hash.write(new_class_hash);
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
