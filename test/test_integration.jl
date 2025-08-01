using Test
using Agent

@testset "Integration Tests" begin
    
    @testset "Multi-Agent System" begin
        # Test multiple agents running concurrently
        mutable struct CounterAgent
            id::Int
            target::Int
            counter::Int
            started::Bool
            finished::Bool
        end
        
        CounterAgent(id::Int, target::Int) = CounterAgent(id, target, 0, false, false)
        
        Agent.name(agent::CounterAgent) = "counter-$(agent.id)"
        Agent.on_start(agent::CounterAgent) = (agent.started = true)
        Agent.on_close(agent::CounterAgent) = (agent.finished = true)
        
        function Agent.do_work(agent::CounterAgent)
            agent.counter += 1
            if agent.counter >= agent.target
                throw(AgentTerminationException())
            end
            return 1
        end
        
        # Create multiple agents with different targets
        agents = [CounterAgent(i, 5 + i) for i in 1:3]
        runners = [AgentRunner(NoOpIdleStrategy(), agent) for agent in agents]
        
        # Start all agents
        for runner in runners
            start_on_thread(runner)
        end
        
        # Wait for all to complete
        for runner in runners
            wait(runner)
        end
        
        # Verify all completed successfully
        for (i, agent) in enumerate(agents)
            @test agent.started
            @test agent.finished
            @test agent.counter >= agent.target
        end
        
        # Clean up
        for runner in runners
            close(runner)
            @test Agent.is_closed(runner)
        end
    end
    
    @testset "Producer-Consumer Pattern" begin
        # Shared data structure
        mutable struct SharedQueue
            items::Vector{Int}
            max_size::Int
        end
        SharedQueue(max_size::Int) = SharedQueue(Int[], max_size)
        
        # Producer agent
        mutable struct ProducerAgent
            queue::SharedQueue
            produced::Int
            target::Int
            finished::Bool
        end
        
        ProducerAgent(queue::SharedQueue, target::Int) = ProducerAgent(queue, 0, target, false)
        
        Agent.name(agent::ProducerAgent) = "producer"
        Agent.on_close(agent::ProducerAgent) = (agent.finished = true)
        
        function Agent.do_work(agent::ProducerAgent)
            if length(agent.queue.items) < agent.queue.max_size && agent.produced < agent.target
                push!(agent.queue.items, agent.produced + 1)
                agent.produced += 1
                return 1  # Work done
            elseif agent.produced >= agent.target
                throw(AgentTerminationException())
            end
            return 0  # No work done (queue full)
        end
        
        # Consumer agent
        mutable struct ConsumerAgent
            queue::SharedQueue
            consumed::Vector{Int}
            target::Int
            finished::Bool
        end
        
        ConsumerAgent(queue::SharedQueue, target::Int) = ConsumerAgent(queue, Int[], target, false)
        
        Agent.name(agent::ConsumerAgent) = "consumer"
        Agent.on_close(agent::ConsumerAgent) = (agent.finished = true)
        
        function Agent.do_work(agent::ConsumerAgent)
            if !isempty(agent.queue.items)
                item = popfirst!(agent.queue.items)
                push!(agent.consumed, item)
                if length(agent.consumed) >= agent.target
                    throw(AgentTerminationException())
                end
                return 1  # Work done
            end
            return 0  # No work done (queue empty)
        end
        
        # Set up producer-consumer system
        queue = SharedQueue(5)
        producer = ProducerAgent(queue, 10)
        consumer = ConsumerAgent(queue, 10)
        
        producer_runner = AgentRunner(YieldingIdleStrategy(), producer)
        consumer_runner = AgentRunner(YieldingIdleStrategy(), consumer)
        
        # Start both agents
        start_on_thread(producer_runner)
        start_on_thread(consumer_runner)
        
        # Wait for both to complete
        wait(producer_runner)
        wait(consumer_runner)
        
        # Verify results
        @test producer.finished
        @test consumer.finished
        @test producer.produced == 10
        @test length(consumer.consumed) == 10
        @test consumer.consumed == collect(1:10)  # Should consume in order
        
        # Clean up
        close(producer_runner)
        close(consumer_runner)
    end
    
    @testset "Error Recovery System" begin
        # Agent that occasionally errors but recovers
        mutable struct RecoveringAgent
            work_count::Int
            error_count::Int
            max_errors::Int
            target_work::Int
            finished::Bool
        end
        
        RecoveringAgent(target::Int, max_errors::Int) = RecoveringAgent(0, 0, max_errors, target, false)
        
        Agent.name(agent::RecoveringAgent) = "recovering"
        Agent.on_close(agent::RecoveringAgent) = (agent.finished = true)
        
        function Agent.on_error(agent::RecoveringAgent, error)
            agent.error_count += 1
            if agent.error_count >= agent.max_errors
                throw(AgentTerminationException())
            end
            # Otherwise, continue running (error is "handled")
        end
        
        function Agent.do_work(agent::RecoveringAgent)
            agent.work_count += 1
            
            # Intentionally error on certain work counts
            if agent.work_count == 3 || agent.work_count == 7
                error("Intentional error $(agent.work_count)")
            end
            
            if agent.work_count >= agent.target_work
                throw(AgentTerminationException())
            end
            
            return 1
        end
        
        agent = RecoveringAgent(10, 3)  # Target 10 work, allow up to 3 errors
        runner = AgentRunner(NoOpIdleStrategy(), agent)
        
        start_on_thread(runner)
        wait(runner)
        
        @test agent.finished
        @test agent.error_count == 2  # Should have hit 2 errors (at work_count 3 and 7)
        @test agent.work_count >= agent.target_work
        
        close(runner)
    end
    
    @testset "Performance Monitoring" begin
        # Agent that tracks performance metrics
        mutable struct MonitoredAgent
            work_count::Int
            start_time::Float64
            end_time::Float64
            work_times::Vector{Float64}
            target::Int
        end
        
        MonitoredAgent(target::Int) = MonitoredAgent(0, 0.0, 0.0, Float64[], target)
        
        Agent.name(agent::MonitoredAgent) = "monitored"
        Agent.on_start(agent::MonitoredAgent) = (agent.start_time = time())
        Agent.on_close(agent::MonitoredAgent) = (agent.end_time = time())
        
        function Agent.do_work(agent::MonitoredAgent)
            work_start = time()
            
            # Simulate varying work loads
            if agent.work_count % 3 == 0
                sleep(0.001)  # Heavier work
            else
                sleep(0.0001)  # Lighter work
            end
            
            work_end = time()
            push!(agent.work_times, work_end - work_start)
            
            agent.work_count += 1
            if agent.work_count >= agent.target
                throw(AgentTerminationException())
            end
            
            return 1
        end
        
        agent = MonitoredAgent(10)
        runner = AgentRunner(BackoffIdleStrategy(), agent)
        
        start_on_thread(runner)
        wait(runner)
        
        # Verify monitoring data
        @test agent.start_time > 0
        @test agent.end_time > agent.start_time
        @test length(agent.work_times) == agent.target
        @test agent.work_count == agent.target
        
        # Check that we captured timing differences
        avg_time = sum(agent.work_times) / length(agent.work_times)
        @test avg_time > 0
        
        close(runner)
    end
    
    @testset "Stress Test - High Frequency Agent" begin
        # Agent that does lots of small work items quickly
        mutable struct HighFrequencyAgent
            work_count::Int
            target::Int
            finished::Bool
        end
        
        HighFrequencyAgent(target::Int) = HighFrequencyAgent(0, target, false)
        
        Agent.name(agent::HighFrequencyAgent) = "high-frequency"
        Agent.on_close(agent::HighFrequencyAgent) = (agent.finished = true)
        
        function Agent.do_work(agent::HighFrequencyAgent)
            agent.work_count += 1
            if agent.work_count >= agent.target
                throw(AgentTerminationException())
            end
            return 1
        end
        
        # Test with busy spin for maximum throughput
        agent = HighFrequencyAgent(1000)
        runner = AgentRunner(BusySpinIdleStrategy(), agent)
        
        start_time = time()
        start_on_thread(runner)
        wait(runner)
        end_time = time()
        
        @test agent.finished
        @test agent.work_count == 1000
        
        # Should complete quickly with busy spin
        execution_time = end_time - start_time
        @test execution_time < 2.0  # Should be much faster than 2 seconds
        
        close(runner)
    end
end