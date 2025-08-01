using Test
using Agent

@testset "Idle Strategy Tests" begin
    
    @testset "NoOpIdleStrategy" begin
        strategy = NoOpIdleStrategy()
        @test isa(strategy, IdleStrategy)
        @test isa(strategy, NoOpIdleStrategy)
        
        # idle() should do nothing and not error
        Agent.idle(strategy)
        Agent.idle(strategy, 0)  # No work
        Agent.idle(strategy, 1)  # Some work
        Agent.idle(strategy, 10) # More work
        
        # reset should do nothing and not error
        Agent.reset(strategy)
        
        @test true  # If we get here, all calls succeeded
    end
    
    @testset "BusySpinIdleStrategy" begin
        strategy = BusySpinIdleStrategy()
        @test isa(strategy, IdleStrategy)
        @test isa(strategy, BusySpinIdleStrategy)
        
        # Test that idle() completes without error (calls CPU pause)
        Agent.idle(strategy)
        Agent.idle(strategy, 0)  # No work
        Agent.idle(strategy, 1)  # Some work
        
        # reset should do nothing and not error
        Agent.reset(strategy)
        
        @test true  # If we get here, all calls succeeded
    end
    
    @testset "YieldingIdleStrategy" begin
        strategy = YieldingIdleStrategy()
        @test isa(strategy, IdleStrategy)
        @test isa(strategy, YieldingIdleStrategy)
        
        # Test that idle() completes without error (calls yield)
        Agent.idle(strategy)
        Agent.idle(strategy, 0)  # No work
        Agent.idle(strategy, 1)  # Some work
        
        # reset should do nothing and not error
        Agent.reset(strategy)
        
        @test true  # If we get here, all calls succeeded
    end
    
    @testset "SleepingIdleStrategy" begin
        # Test with valid sleep time (1 microsecond)
        strategy = SleepingIdleStrategy(1000)  # 1000 nanoseconds = 1 microsecond
        @test isa(strategy, IdleStrategy)
        @test isa(strategy, SleepingIdleStrategy)
        @test strategy.sleeptime == 1000
        
        # Test that idle() completes without error
        Agent.idle(strategy)
        Agent.idle(strategy, 0)  # No work
        Agent.idle(strategy, 1)  # Some work
        
        # Test construction with invalid sleep time
        @test_throws ErrorException SleepingIdleStrategy(1_000_000_000)  # 1 second, too long
        @test_throws ErrorException SleepingIdleStrategy(2_000_000_000)  # Even longer
        
        # reset should do nothing and not error
        Agent.reset(strategy)
        
        @test true  # If we get here, valid calls succeeded
    end
    
    @testset "SleepingMillisIdleStrategy" begin
        # Test with various sleep times
        strategy = SleepingMillisIdleStrategy(10)  # 10 milliseconds
        @test isa(strategy, IdleStrategy)
        @test isa(strategy, SleepingMillisIdleStrategy)
        @test strategy.sleeptime ≈ 0.01  # 10ms converted to seconds
        
        strategy2 = SleepingMillisIdleStrategy(100)  # 100 milliseconds
        @test strategy2.sleeptime ≈ 0.1  # 100ms converted to seconds
        
        # Test that idle() completes without error
        Agent.idle(strategy)
        Agent.idle(strategy, 0)  # No work
        Agent.idle(strategy, 1)  # Some work
        
        # reset should do nothing and not error
        Agent.reset(strategy)
        
        @test true  # If we get here, all calls succeeded
    end
    
    @testset "BackoffIdleStrategy" begin
        # Test default constructor
        strategy = BackoffIdleStrategy()
        @test isa(strategy, IdleStrategy)
        @test isa(strategy, BackoffIdleStrategy)
        
        # Test custom constructor
        strategy2 = BackoffIdleStrategy(5, 3, 500, 50000)
        @test strategy2.max_spins == 5
        @test strategy2.max_yields == 3
        @test strategy2.min_park_period_ns == 500
        @test strategy2.max_park_period_ns == 50000
        
        # Test initial state
        @test strategy.spins == 0
        @test strategy.yields == 0
        @test strategy.park_period_ns == 0
        
        # Test reset functionality
        strategy.spins = 5
        strategy.yields = 3
        strategy.park_period_ns = 1000
        Agent.reset(strategy)
        @test strategy.spins == 0
        @test strategy.yields == 0
        @test strategy.park_period_ns == strategy.min_park_period_ns
        
        # Test idle with work (should reset)
        strategy.spins = 5
        Agent.idle(strategy, 1)  # Work done
        @test strategy.spins == 0  # Should be reset
        
        # Test idle without work (should progress through states)
        strategy_test = BackoffIdleStrategy(2, 2, 1000, 10000)  # Small values for testing
        Agent.reset(strategy_test)
        
        # Should start in NOT_IDLE, then progress to SPINNING
        Agent.idle(strategy_test, 0)  # No work
        @test strategy_test.spins == 1
        
        Agent.idle(strategy_test, 0)  # No work
        @test strategy_test.spins == 2
        
        Agent.idle(strategy_test, 0)  # No work, should exceed max_spins and move to yielding
        @test strategy_test.spins == 3
        @test strategy_test.yields == 0
        
        # Continue to test yielding phase
        Agent.idle(strategy_test, 0)  # Should be yielding now
        @test strategy_test.yields == 1
        
        Agent.idle(strategy_test, 0)
        @test strategy_test.yields == 2
        
        Agent.idle(strategy_test, 0)  # Should exceed max_yields and move to parking
        @test strategy_test.yields == 3
        @test strategy_test.park_period_ns == strategy_test.min_park_period_ns
        
        # Test parking phase (just ensure no errors)
        Agent.idle(strategy_test, 0)  # Should park
        @test strategy_test.park_period_ns > strategy_test.min_park_period_ns  # Should backoff
    end
    
    @testset "Generic IdleStrategy Interface" begin
        # Test that all strategies implement the interface correctly
        strategies = [
            NoOpIdleStrategy(),
            BusySpinIdleStrategy(),
            YieldingIdleStrategy(),
            SleepingIdleStrategy(1000),
            SleepingMillisIdleStrategy(1),
            BackoffIdleStrategy()
        ]
        
        for strategy in strategies
            @test isa(strategy, IdleStrategy)
            
            # Test idle with work count
            Agent.idle(strategy, 0)  # No work
            Agent.idle(strategy, 1)  # Some work
            Agent.idle(strategy, -1) # Error condition (no work)
            
            # Test reset
            Agent.reset(strategy)
        end
    end
end