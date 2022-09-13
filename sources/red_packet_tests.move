#[test_only]
module std::red_packet_tests {
    use std::signer;
    use std::vector;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::aptos_account;
    use aptos_framework::coin;
    use aptos_framework::managed_coin::Self;

    use RedPacket::red_packet::{
        Self, initialize, create, open, close, set_admin, set_base_prepaid_fee,
        set_fee_point, batch_close, register_coin, TestCoin
    };

    #[test_only]
    fun setup_test_coin(
        minter: &signer,
        receiver: &signer,
        balance: u64
    ) {
        let minter_addr = signer::address_of(minter);
        let receiver_addr = signer::address_of(receiver);

        if (!coin::is_coin_initialized<TestCoin>()) {
            managed_coin::initialize<TestCoin>(
                minter,
                b"Test Coin",
                b"Test",
                8u8,
                true
            );
        };

        if (!coin::is_account_registered<TestCoin>(minter_addr)) {
            coin::register<TestCoin>(minter);
        };

        if (!coin::is_account_registered<TestCoin>(receiver_addr)) {
            coin::register<TestCoin>(receiver)
        };

        managed_coin::mint<TestCoin>(
            minter,
            receiver_addr,
            balance
        )
    }

    #[test_only]
    fun setup_aptos(
        aptos_framework: &signer,
        account: &signer,
        balance: u64
    ) {
        if (!coin::is_coin_initialized<AptosCoin>()) {
            let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
            coin::destroy_mint_cap<AptosCoin>(mint_cap);
            coin::destroy_burn_cap<AptosCoin>(burn_cap);
        };

        let account_addr = signer::address_of(account);
        aptos_account::create_account(account_addr);
        aptos_coin::mint(aptos_framework, account_addr, balance);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234
    )]
    fun initialize_should_work(
        aptos_framework: signer,
        operator: &signer,
        beneficiary: address
    ) {
        setup_aptos(&aptos_framework, operator, 0);

        let operator_addr = signer::address_of(operator);
        initialize(operator, beneficiary, beneficiary);

        red_packet::check_operator(operator_addr, true);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234
    )]
    #[expected_failure(abort_code = 524291)]
    fun initialize_twice_should_fail(
        aptos_framework: signer,
        operator: &signer,
        beneficiary: address
    ) {
        setup_aptos(&aptos_framework, operator, 0);

        let operator_addr = signer::address_of(operator);
        initialize(operator, beneficiary, beneficiary);

        red_packet::check_operator(operator_addr, true);

        initialize(operator, beneficiary, beneficiary);
    }

    #[test(
        aptos_framework = @aptos_framework,
        beneficiary = @0x234,
        lucky = @0x345
    )]
    #[expected_failure(abort_code = 327682)]
    fun initialize_other_should_fail(
        aptos_framework: signer,
        lucky: &signer,
        beneficiary: address
    ) {
        setup_aptos(&aptos_framework, lucky, 0);

        initialize(lucky, beneficiary, beneficiary);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234
    )]
    fun create_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: signer
    ) {
        setup_aptos(&aptos_framework, &operator, 10000);
        setup_aptos(&aptos_framework, &beneficiary, 0);

        let beneficiary_addr = signer::address_of(&beneficiary);

        initialize(&operator, beneficiary_addr, beneficiary_addr);

        register_coin<AptosCoin>(&operator);

        create<AptosCoin>(&operator, 10, 10000);

        assert!(coin::balance<AptosCoin>(beneficiary_addr) == 250, 0);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234
    )]
    fun create_testcoin_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: signer
    ) {
        // creator, tranfer APT as prepaid fee
        setup_aptos(&aptos_framework, &operator, 1000);
        // admin, receive APT as prepaid fee
        setup_aptos(&aptos_framework, &beneficiary, 0);
        // creator, transfer TestCoin
        setup_test_coin(&operator, &operator, 10000);
        // beneficiary, receive TestCoin
        setup_test_coin(&operator, &beneficiary, 0);

        let beneficiary_addr = signer::address_of(&beneficiary);
        let operator_addr = signer::address_of(&operator);

        initialize(&operator, beneficiary_addr, beneficiary_addr);

        register_coin<TestCoin>(&operator);

        assert!(coin::balance<TestCoin>(operator_addr) == 10000, 0);
        assert!(coin::balance<AptosCoin>(operator_addr) == 1000, 1);

        assert!(red_packet::base_prepaid() == 4, 2);

        // 1. pay some prepaid fee to admin: 4 * 10 = 40
        // 2. trasfer some TestCoin to contract: 10000
        create<TestCoin>(&operator, 10, 10000);

        assert!(coin::balance<TestCoin>(beneficiary_addr) == 250, 3);
        assert!(coin::balance<AptosCoin>(operator_addr) == 960, 4);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234
    )]
    #[expected_failure]
    fun create_should_fail_without_register(
        aptos_framework: signer,
        operator: signer,
        beneficiary: signer
    ) {
        setup_aptos(&aptos_framework, &operator, 10000);
        setup_aptos(&aptos_framework, &beneficiary, 0);

        let beneficiary_addr = signer::address_of(&beneficiary);

        initialize(&operator, beneficiary_addr, beneficiary_addr);

        create<AptosCoin>(&operator, 10, 10000);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234,
        lucky1 = @0x888,
        lucky2 = @0x999,
    )]
    fun open_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: signer,
        lucky1: signer,
        lucky2: signer,
    ) {
        setup_aptos(&aptos_framework, &operator, 100000);
        setup_aptos(&aptos_framework, &beneficiary, 0);
        setup_aptos(&aptos_framework, &lucky1, 0);
        setup_aptos(&aptos_framework, &lucky2, 0);

        let operator_addr = signer::address_of(&operator);
        let beneficiary_addr = signer::address_of(&beneficiary);

        initialize(&operator, beneficiary_addr, beneficiary_addr);

        register_coin<AptosCoin>(&operator);

        assert!(coin::balance<AptosCoin>(operator_addr) == 100000, 0);

        create<AptosCoin>(&operator, 2, 10000);

        assert!(red_packet::current_id() == 2, 1);
        assert!(red_packet::remain_count(1) == 2, 2);

        // 97.5%
        assert!(red_packet::escrow_coins(1) == 10000 - 250, 3);
        // 2.5%
        assert!(coin::balance<AptosCoin>(beneficiary_addr) == 250, 4);

        assert!(coin::balance<AptosCoin>(operator_addr) == 90000, 5);

        let accounts = vector::empty<address>();
        let lucky1_addr = signer::address_of(&lucky1);
        let lucky2_addr = signer::address_of(&lucky2);
        vector::push_back(&mut accounts, lucky1_addr);
        vector::push_back(&mut accounts, lucky2_addr);

        let balances = vector::empty<u64>();
        vector::push_back(&mut balances, 1000);
        vector::push_back(&mut balances, 8750);

        open<AptosCoin>(&operator, 1, accounts, balances);

        assert!(red_packet::remain_count(1) == 0, 6);
        assert!(red_packet::escrow_coins(1) == 0, 7);

        assert!(coin::balance<AptosCoin>(lucky1_addr) == 1000, 8);
        assert!(coin::balance<AptosCoin>(lucky2_addr) == 8750, 9);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234,
        lucky1 = @0x888,
        lucky2 = @0x999,
    )]
    fun open_testcoin_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: signer,
        lucky1: signer,
        lucky2: signer,
    ) {
        // creator, tranfer APT as prepaid fee
        setup_aptos(&aptos_framework, &operator, 1000);
        // admin, receive APT as prepaid fee
        setup_aptos(&aptos_framework, &beneficiary, 0);
        // register account
        setup_aptos(&aptos_framework, &lucky1, 0);
        // register account
        setup_aptos(&aptos_framework, &lucky2, 0);
        // creator, transfer TestCoin
        setup_test_coin(&operator, &operator, 100000);
        // beneficiary, receive TestCoin
        setup_test_coin(&operator, &beneficiary, 0);
        // lucky account, receive TestCoin
        setup_test_coin(&operator, &lucky1, 0);
        // lucky account, receive TestCoin
        setup_test_coin(&operator, &lucky2, 0);

        let operator_addr = signer::address_of(&operator);
        let beneficiary_addr = signer::address_of(&beneficiary);

        initialize(&operator, beneficiary_addr, beneficiary_addr);

        register_coin<TestCoin>(&operator);

        assert!(coin::balance<AptosCoin>(operator_addr) == 1000, 0);
        assert!(coin::balance<TestCoin>(operator_addr) == 100000, 1);

        create<TestCoin>(&operator, 2, 10000);
        // prepaid fee: 2 * 4 = 8
        assert!(coin::balance<AptosCoin>(operator_addr) == 1000 - 2 * 4, 2);

        assert!(red_packet::current_id() == 2, 3);
        assert!(red_packet::remain_count(1) == 2, 4);

        // 97.5%
        assert!(red_packet::escrow_coins(1) == 10000 - 250, 5);
        // 2.5%
        assert!(coin::balance<TestCoin>(beneficiary_addr) == 250, 6);

        assert!(coin::balance<TestCoin>(operator_addr) == 90000, 7);

        let accounts = vector::empty<address>();
        let lucky1_addr = signer::address_of(&lucky1);
        let lucky2_addr = signer::address_of(&lucky2);
        vector::push_back(&mut accounts, lucky1_addr);
        vector::push_back(&mut accounts, lucky2_addr);

        let balances = vector::empty<u64>();
        vector::push_back(&mut balances, 1000);
        vector::push_back(&mut balances, 8750);

        open<TestCoin>(&operator, 1, accounts, balances);

        assert!(red_packet::remain_count(1) == 0, 8);
        assert!(red_packet::escrow_coins(1) == 0, 9);

        assert!(coin::balance<TestCoin>(lucky1_addr) == 1000, 10);
        assert!(coin::balance<TestCoin>(lucky2_addr) == 8750, 11);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        creator = @0x222,
        beneficiary = @0x234,
        lucky1 = @0x888,
        lucky2 = @0x999,
    )]
    fun close_should_work(
        aptos_framework: signer,
        operator: signer,
        creator: signer,
        beneficiary: signer,
        lucky1: signer,
        lucky2: signer,
    ) {
        setup_aptos(&aptos_framework, &operator, 0);
        setup_aptos(&aptos_framework, &creator, 100000);
        setup_aptos(&aptos_framework, &beneficiary, 0);
        setup_aptos(&aptos_framework, &lucky1, 0);
        setup_aptos(&aptos_framework, &lucky2, 0);

        let creator_addr = signer::address_of(&creator);
        let beneficiary_addr = signer::address_of(&beneficiary);

        initialize(&operator, beneficiary_addr, beneficiary_addr);

        register_coin<AptosCoin>(&operator);

        assert!(coin::balance<AptosCoin>(creator_addr) == 100000, 0);

        create<AptosCoin>(&creator, 3, 30000);

        assert!(red_packet::current_id() == 2, 1);
        assert!(red_packet::remain_count(1) == 3, 2);

        // 97.5%
        assert!(red_packet::escrow_coins(1) == 30000 - 750 , 3);
        // 2.5%
        assert!(coin::balance<AptosCoin>(beneficiary_addr) == 750, 4);

        assert!(coin::balance<AptosCoin>(creator_addr) == 70000, 5);

        let accounts = vector::empty<address>();
        let lucky1_addr = signer::address_of(&lucky1);
        let lucky2_addr = signer::address_of(&lucky2);
        vector::push_back(&mut accounts, lucky1_addr);
        vector::push_back(&mut accounts, lucky2_addr);

        let balances = vector::empty<u64>();
        vector::push_back(&mut balances, 1000);
        vector::push_back(&mut balances, 9000);

        open<AptosCoin>(&operator, 1, accounts, balances);

        assert!(red_packet::remain_count(1) == 1, 7);
        assert!(red_packet::escrow_coins(1) == 19250, 8);

        close<AptosCoin>(&operator, 1);

        assert!(coin::balance<AptosCoin>(lucky1_addr) == 1000, 9);
        assert!(coin::balance<AptosCoin>(lucky2_addr) == 9000, 10);
        assert!(coin::balance<AptosCoin>(beneficiary_addr) == 750 + 19250, 11);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        creator = @0x222,
        beneficiary = @0x234,
        lucky1 = @0x888,
        lucky2 = @0x999,
    )]
    fun close_testcoin_should_work(
        aptos_framework: signer,
        operator: signer,
        creator: signer,
        beneficiary: signer,
        lucky1: signer,
        lucky2: signer,
    ) {
        // minter, mint TestCoin
        setup_aptos(&aptos_framework, &operator, 0);
        // creator, tranfer APT as prepaid fee
        setup_aptos(&aptos_framework, &creator, 1000);
        // admin, receive APT as prepaid fee
        setup_aptos(&aptos_framework, &beneficiary, 0);
        // register account
        setup_aptos(&aptos_framework, &lucky1, 0);
        // register account
        setup_aptos(&aptos_framework, &lucky2, 0);
        // creator, transfer TestCoin
        setup_test_coin(&operator, &creator, 100000);
        // beneficiary, receive TestCoin
        setup_test_coin(&operator, &beneficiary, 0);
        // lucky account, receive TestCoin
        setup_test_coin(&operator, &lucky1, 0);
        // lucky account, receive TestCoin
        setup_test_coin(&operator, &lucky2, 0);

        let creator_addr = signer::address_of(&creator);
        let beneficiary_addr = signer::address_of(&beneficiary);

        initialize(&operator, beneficiary_addr, beneficiary_addr);

        register_coin<TestCoin>(&operator);

        assert!(coin::balance<TestCoin>(creator_addr) == 100000, 0);
        assert!(coin::balance<AptosCoin>(creator_addr) == 1000, 1);

        create<TestCoin>(&creator, 3, 30000);

        assert!(coin::balance<AptosCoin>(creator_addr) == 1000 - 3 * 4, 1);

        assert!(red_packet::current_id() == 2, 1);
        assert!(red_packet::remain_count(1) == 3, 2);

        // 97.5%
        assert!(red_packet::escrow_coins(1) == 30000 - 750 , 3);
        // 2.5%
        assert!(coin::balance<TestCoin>(beneficiary_addr) == 750, 4);

        assert!(coin::balance<TestCoin>(creator_addr) == 70000, 5);

        let accounts = vector::empty<address>();
        let lucky1_addr = signer::address_of(&lucky1);
        let lucky2_addr = signer::address_of(&lucky2);
        vector::push_back(&mut accounts, lucky1_addr);
        vector::push_back(&mut accounts, lucky2_addr);

        let balances = vector::empty<u64>();
        vector::push_back(&mut balances, 1000);
        vector::push_back(&mut balances, 9000);

        open<TestCoin>(&operator, 1, accounts, balances);

        assert!(red_packet::remain_count(1) == 1, 7);
        assert!(red_packet::escrow_coins(1) == 19250, 8);

        close<TestCoin>(&operator, 1);

        assert!(coin::balance<TestCoin>(lucky1_addr) == 1000, 9);
        assert!(coin::balance<TestCoin>(lucky2_addr) == 9000, 10);
        assert!(coin::balance<TestCoin>(beneficiary_addr) == 750 + 19250, 11);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        creator = @0x222,
        beneficiary = @0x234,
        lucky1 = @0x888,
        lucky2 = @0x999,
    )]
    fun batch_close_should_work(
        aptos_framework: signer,
        operator: signer,
        creator: signer,
        beneficiary: signer,
        lucky1: signer,
        lucky2: signer,
    ) {
        setup_aptos(&aptos_framework, &operator, 0);
        setup_aptos(&aptos_framework, &creator, 100000);
        setup_aptos(&aptos_framework, &beneficiary, 0);
        setup_aptos(&aptos_framework, &lucky1, 0);
        setup_aptos(&aptos_framework, &lucky2, 0);

        let creator_addr = signer::address_of(&creator);
        let beneficiary_addr = signer::address_of(&beneficiary);

        initialize(&operator, beneficiary_addr, beneficiary_addr);

        register_coin<AptosCoin>(&operator);

        assert!(coin::balance<AptosCoin>(creator_addr) == 100000, 0);
        assert!(red_packet::current_id() == 1, 1);

        create<AptosCoin>(&creator, 3, 30000);
        create<AptosCoin>(&creator, 3, 30000);
        create<AptosCoin>(&creator, 3, 30000);

        assert!(red_packet::current_id() == 4, 2);
        assert!(red_packet::remain_count(1) == 3, 3);
        assert!(red_packet::remain_count(2) == 3, 4);
        assert!(red_packet::remain_count(3) == 3, 5);

        // 97.5%
        assert!(red_packet::escrow_coins(1) == 30000 - 750 , 6);
        assert!(red_packet::escrow_coins(2) == 30000 - 750 , 7);
        assert!(red_packet::escrow_coins(3) == 30000 - 750 , 8);

        // 2.5%
        assert!(coin::balance<AptosCoin>(beneficiary_addr) == 750 * 3, 9);

        assert!(coin::balance<AptosCoin>(creator_addr) == 10000, 10);

        let accounts = vector::empty<address>();
        let lucky1_addr = signer::address_of(&lucky1);
        let lucky2_addr = signer::address_of(&lucky2);
        vector::push_back(&mut accounts, lucky1_addr);
        vector::push_back(&mut accounts, lucky2_addr);

        let balances = vector::empty<u64>();
        vector::push_back(&mut balances, 1000);
        vector::push_back(&mut balances, 9000);

        open<AptosCoin>(&operator, 1, accounts, balances);

        assert!(red_packet::remain_count(1) == 1, 11);
        assert!(red_packet::escrow_coins(1) == 19250, 12);

        batch_close<AptosCoin>(&operator, 1, 4);
        // batch close again
        batch_close<AptosCoin>(&operator, 1, 4);

        assert!(coin::balance<AptosCoin>(lucky1_addr) == 1000, 13);
        assert!(coin::balance<AptosCoin>(lucky2_addr) == 9000, 14);
        assert!(coin::balance<AptosCoin>(beneficiary_addr) == 750 + 19250 + 60000, 15);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234,
        admin = @0x345,
        new_admin = @0x456,
    )]
    fun set_admin_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: signer,
        admin: signer,
        new_admin: signer,
    ) {
        setup_aptos(&aptos_framework, &operator, 0);
        setup_aptos(&aptos_framework, &admin, 10000);
        setup_aptos(&aptos_framework, &beneficiary, 0);
        setup_aptos(&aptos_framework, &new_admin, 100);

        let operator_addr = signer::address_of(&operator);
        let beneficiary_addr = signer::address_of(&beneficiary);
        let admin_addr = signer::address_of(&admin);
        let new_admin_addr = signer::address_of(&new_admin);

        initialize(&operator, beneficiary_addr, admin_addr);
        red_packet::check_operator(operator_addr, true);
        register_coin<AptosCoin>(&operator);

        assert!(red_packet::admin() == admin_addr, 0);
        set_admin(&operator, new_admin_addr);
        assert!(red_packet::admin() == new_admin_addr, 1);

        assert!(red_packet::base_prepaid() == 4, 2);

        create<AptosCoin>(&admin, 1, 10000);

        // 97.5%

        assert!(red_packet::escrow_coins(1) == 10000 - 250, 3);

        // 2.5%

        assert!(coin::balance<AptosCoin>(beneficiary_addr) == 250 - 4, 4);
        assert!(coin::balance<AptosCoin>(new_admin_addr) == 100 + 4, 5);

        let accounts = vector::empty<address>();
        vector::push_back(&mut accounts, admin_addr);
        let balances = vector::empty<u64>();
        vector::push_back(&mut balances, 10000 - 250 - 100);

        open<AptosCoin>(&new_admin, 1, accounts, balances);
        assert!(coin::balance<AptosCoin>(admin_addr) == 10000 - 250 - 100, 6);
        assert!(coin::balance<AptosCoin>(new_admin_addr) == 100 + 4, 7);

        close<AptosCoin>(&new_admin, 1);
        assert!(coin::balance<AptosCoin>(beneficiary_addr) == 250 - 4 + 100, 8);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234,
        admin = @0x345,
    )]
    fun set_point_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: signer,
        admin: signer,
    ) {
        setup_aptos(&aptos_framework, &operator, 0);
        setup_aptos(&aptos_framework, &admin, 100);
        setup_aptos(&aptos_framework, &beneficiary, 0);

        let operator_addr = signer::address_of(&operator);
        let beneficiary_addr = signer::address_of(&beneficiary);
        let admin_addr = signer::address_of(&admin);

        initialize(&operator, beneficiary_addr, admin_addr);
        red_packet::check_operator(operator_addr, true);
        register_coin<AptosCoin>(&operator);

        // 2.5%
        assert!(red_packet::fee_point() == 250, 0);

        set_fee_point(&operator, 100);

        // 1%
        assert!(red_packet::fee_point() == 100, 1);
    }

    #[test(
        aptos_framework = @aptos_framework,
        operator = @0x123,
        beneficiary = @0x234,
        admin = @0x345,
    )]
    fun set_base_prepaid_fee_should_work(
        aptos_framework: signer,
        operator: signer,
        beneficiary: signer,
        admin: signer,
    ) {
        setup_aptos(&aptos_framework, &operator, 0);
        setup_aptos(&aptos_framework, &admin, 100);
        setup_aptos(&aptos_framework, &beneficiary, 0);

        let operator_addr = signer::address_of(&operator);
        let beneficiary_addr = signer::address_of(&beneficiary);
        let admin_addr = signer::address_of(&admin);

        initialize(&operator, beneficiary_addr, admin_addr);
        red_packet::check_operator(operator_addr, true);
        register_coin<AptosCoin>(&operator);

        // 4
        assert!(red_packet::base_prepaid() == 4, 0);

        set_base_prepaid_fee(&operator, 40);

        // 40
        assert!(red_packet::base_prepaid() == 40, 1);
    }
}
