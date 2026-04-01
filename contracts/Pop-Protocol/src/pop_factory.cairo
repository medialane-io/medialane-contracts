/// POPFactory — Multi-tenant factory for Proof of Participation collections.
///
/// Any organisation granted ORGANIZER_ROLE (a "provider") can deploy their own
/// soulbound NFT collection for events, classes, bootcamps, or quests.
///
/// The factory:
///   - Registers and revokes providers (organisations)
///   - Deploys independent POPCollection contracts per event
///   - Passes platform_admin to each collection for emergency override capability
///   - Maintains a per-provider collection index for on-chain discovery

#[starknet::contract]
pub mod POPFactory {
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

    use crate::interfaces::IPOPFactory::IPOPFactory;
    use crate::events::{CollectionCreated, ProviderRegistered, ProviderRevoked};
    use crate::types::{CollectionRecord, ProviderRecord, EventType};

    /// Role for organisations authorised to create collections.
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
        /// The Mediolano platform admin address, passed to every deployed collection
        /// so the platform can always exercise emergency override on any collection.
        platform_admin: ContractAddress,
        /// Class hash of POPCollection used for each deploy_syscall.
        pop_collection_class_hash: ClassHash,
        /// Auto-incrementing collection counter.
        last_collection_id: u256,
        /// collection_id → CollectionRecord
        collections: Map<u256, CollectionRecord>,
        /// provider_address → ProviderRecord
        providers: Map<ContractAddress, ProviderRecord>,
        /// provider → number of collections they have created
        provider_collection_count: Map<ContractAddress, u32>,
        /// (provider, index) → collection_id  — for paginated on-chain queries
        provider_collections: Map<(ContractAddress, u32), u256>,
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
        CollectionCreated: CollectionCreated,
        ProviderRegistered: ProviderRegistered,
        ProviderRevoked: ProviderRevoked,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        pop_collection_class_hash: ClassHash,
    ) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, admin);
        // Admin bootstraps their own collections too
        self.accesscontrol._grant_role(ORGANIZER_ROLE, admin);
        self.platform_admin.write(admin);
        self.pop_collection_class_hash.write(pop_collection_class_hash);
    }

    #[abi(embed_v0)]
    impl POPFactoryImpl of IPOPFactory<ContractState> {
        // ── Provider management ───────────────────────────────────────────────

        fn register_provider(
            ref self: ContractState,
            provider: ContractAddress,
            name: ByteArray,
            website: ByteArray,
        ) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            assert(!provider.is_zero(), 'Invalid provider address');
            assert(name.len() > 0, 'Provider name cannot be empty');

            self.accesscontrol._grant_role(ORGANIZER_ROLE, provider);

            self
                .providers
                .entry(provider)
                .write(
                    ProviderRecord {
                        name: name.clone(),
                        website: website.clone(),
                        active: true,
                        registered_at: get_block_timestamp(),
                    },
                );

            self
                .emit(
                    ProviderRegistered {
                        provider, name, website, timestamp: get_block_timestamp(),
                    },
                );
        }

        fn revoke_provider(ref self: ContractState, provider: ContractAddress) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            assert(!provider.is_zero(), 'Invalid provider address');

            self.accesscontrol._revoke_role(ORGANIZER_ROLE, provider);

            let mut record = self.providers.entry(provider).read();
            record.active = false;
            self.providers.entry(provider).write(record);

            self.emit(ProviderRevoked { provider, timestamp: get_block_timestamp() });
        }

        fn get_provider(self: @ContractState, provider: ContractAddress) -> ProviderRecord {
            self.providers.entry(provider).read()
        }

        fn is_active_provider(self: @ContractState, provider: ContractAddress) -> bool {
            self.providers.entry(provider).read().active
        }

        // ── Collection management ─────────────────────────────────────────────

        fn create_collection(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            base_uri: ByteArray,
            event_type: EventType,
            claim_end_time: u64,
        ) -> ContractAddress {
            self.accesscontrol.assert_only_role(ORGANIZER_ROLE);
            assert(name.len() > 0, 'Collection name cannot be empty');

            let organizer = get_caller_address();
            let platform_admin = self.platform_admin.read();
            let next_id = self.last_collection_id.read() + 1;
            let timestamp = get_block_timestamp();

            // Serialize constructor args — order must match POPCollection constructor.
            let mut calldata: Array<felt252> = array![];
            (
                name.clone(),
                symbol.clone(),
                base_uri,
                next_id,
                platform_admin,
                organizer,
                claim_end_time,
            )
                .serialize(ref calldata);

            let (collection_address, _) = deploy_syscall(
                self.pop_collection_class_hash.read(),
                next_id.try_into().unwrap(), // deterministic salt
                calldata.span(),
                false,
            )
                .unwrap();

            // Store collection record
            self
                .collections
                .entry(next_id)
                .write(
                    CollectionRecord {
                        collection_id: next_id,
                        name: name.clone(),
                        symbol: symbol.clone(),
                        event_type,
                        organizer,
                        collection_address,
                        created_at: timestamp,
                    },
                );
            self.last_collection_id.write(next_id);

            // Update provider→collections index
            let pc_index = self.provider_collection_count.entry(organizer).read();
            self.provider_collections.entry((organizer, pc_index)).write(next_id);
            self.provider_collection_count.entry(organizer).write(pc_index + 1);

            self
                .emit(
                    CollectionCreated {
                        collection_id: next_id,
                        organizer,
                        collection_address,
                        event_type,
                        name,
                        timestamp,
                    },
                );

            collection_address
        }

        fn get_collection(self: @ContractState, collection_id: u256) -> CollectionRecord {
            self.collections.entry(collection_id).read()
        }

        fn get_collection_address(self: @ContractState, collection_id: u256) -> ContractAddress {
            self.collections.entry(collection_id).read().collection_address
        }

        fn get_last_collection_id(self: @ContractState) -> u256 {
            self.last_collection_id.read()
        }

        fn get_provider_collection_count(
            self: @ContractState, provider: ContractAddress,
        ) -> u32 {
            self.provider_collection_count.entry(provider).read()
        }

        fn get_provider_collection_ids(
            self: @ContractState, provider: ContractAddress, start: u32, count: u32,
        ) -> Array<u256> {
            let total = self.provider_collection_count.entry(provider).read();
            let mut result: Array<u256> = array![];
            let end = start + count;
            let mut i = start;
            loop {
                if i >= end || i >= total {
                    break;
                }
                result.append(self.provider_collections.entry((provider, i)).read());
                i += 1;
            };
            result
        }

        fn get_pop_collection_class_hash(self: @ContractState) -> ClassHash {
            self.pop_collection_class_hash.read()
        }

        fn set_pop_collection_class_hash(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.pop_collection_class_hash.write(new_class_hash);
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
