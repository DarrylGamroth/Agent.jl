using Test
using Agent

@testset "Agent Interface Tests" begin
    
    @testset "AgentTerminationException" begin
        @test AgentTerminationException <: Exception
        exception = AgentTerminationException()
        @test isa(exception, AgentTerminationException)
    end
    
    @testset "Default Agent Interface Methods" begin
        # Test agent for interface testing
        mutable struct TestAgent
            name::String
            start_called::Bool
            close_called::Bool
            error_called::Bool
            work_count::Int
        end
        
        TestAgent(name::String) = TestAgent(name, false, false, false, 0)
        
        # Test custom implementations
        Agent.name(agent::TestAgent) = agent.name
        Agent.on_start(agent::TestAgent) = (agent.start_called = true)
        Agent.on_close(agent::TestAgent) = (agent.close_called = true)
        Agent.on_error(agent::TestAgent, error) = (agent.error_called = true)
        Agent.do_work(agent::TestAgent) = (agent.work_count += 1; 1)
        
        agent = TestAgent("test-agent")
        
        @test Agent.name(agent) == "test-agent"
        
        Agent.on_start(agent)
        @test agent.start_called == true
        
        Agent.on_close(agent)
        @test agent.close_called == true
        
        Agent.on_error(agent, "test error")
        @test agent.error_called == true
        
        work_result = Agent.do_work(agent)
        @test work_result == 1
        @test agent.work_count == 1
    end
    
    @testset "Minimal Agent Implementation" begin
        # Minimal agent that only implements required methods
        mutable struct MinimalAgent
            counter::Int
        end
        MinimalAgent() = MinimalAgent(0)
        
        Agent.name(agent::MinimalAgent) = "minimal"
        Agent.do_work(agent::MinimalAgent) = (agent.counter += 1; 1)
        
        agent = MinimalAgent()
        @test Agent.name(agent) == "minimal"
        @test Agent.do_work(agent) == 1
        @test agent.counter == 1
        
        # Test default implementations (should not error)
        Agent.on_start(agent)  # Should do nothing
        Agent.on_close(agent)  # Should do nothing
    end
    
    @testset "Agent Error Handling" begin
        # Agent that throws errors to test error handling
        mutable struct ErrorAgent
            should_error::Bool
        end
        
        Agent.name(agent::ErrorAgent) = "error-agent"
        Agent.do_work(agent::ErrorAgent) = agent.should_error ? error("Test error") : 1
        
        agent = ErrorAgent(false)
        @test Agent.do_work(agent) == 1
        
        agent.should_error = true
        @test_throws ErrorException Agent.do_work(agent)
    end
    
    @testset "Agent Interface Methods Not Implemented" begin
        # Test agent without implementing required methods
        struct IncompleteAgent end
        
        agent = IncompleteAgent()
        
        # Should throw MethodError for unimplemented do_work
        @test_throws MethodError Agent.do_work(agent)
        
        # Should throw MethodError for unimplemented name
        @test_throws MethodError Agent.name(agent)
    end
    
    @testset "Agent Termination" begin
        # Agent that can terminate itself
        mutable struct TerminatingAgent
            counter::Int
            max_work::Int
        end
        
        Agent.name(agent::TerminatingAgent) = "terminating"
        function Agent.do_work(agent::TerminatingAgent)
            agent.counter += 1
            if agent.counter >= agent.max_work
                throw(AgentTerminationException())
            end
            return 1
        end
        
        agent = TerminatingAgent(0, 3)
        @test Agent.do_work(agent) == 1  # counter = 1
        @test Agent.do_work(agent) == 1  # counter = 2
        @test_throws AgentTerminationException Agent.do_work(agent)  # counter = 3, terminates
    end
    
    @testset "Agent Default Error Behavior" begin
        # Test default on_error behavior (should re-throw)
        mutable struct DefaultErrorAgent end
        
        Agent.name(agent::DefaultErrorAgent) = "default-error"
        Agent.do_work(agent::DefaultErrorAgent) = 1
        
        agent = DefaultErrorAgent()
        test_error = ErrorException("test error")
        
        # Default on_error should re-throw the error
        @test_throws ErrorException Agent.on_error(agent, test_error)
    end
end