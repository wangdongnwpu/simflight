function [x0, u0, lib] = FindLeftTrimDrake(p, lib)
    %% find fixed point

    if nargin < 2
        lib = TrajectoryLibrary(p);
    end
    
    desired_roll = deg2rad(-30);
    
    initial_guess = [desired_roll; 0; 12; 0; 0; 0; p.umax(3)-.5];
    num_decision_vars = length(initial_guess);
    
    
    disp('Searching for fixed point...');
    
    prog = NonlinearProgram(num_decision_vars);

    func = @(in) tbsc_model_for_turn(in(1:4), in(5:7), p.parameters);


    % min_xdot = 5;
    % max_xdot = 30;
    % 
    min_pitch = -1.4;
    max_pitch = 1.4;

    % constraint on:
    % 3 z-ddot_body
    % 4 roll-ddot
    % 5 pitch-ddot
    
    num_constraints = 4;
    lb = zeros(num_constraints, 1);
    ub = zeros(num_constraints, 1);
    
    c = FunctionHandleConstraint( lb, ub, num_decision_vars, func);
    c.grad_method = 'numerical';
    prog = prog.addConstraint(c);
    
    %CostFunc = @(in) abs(in(1)-desired_roll);
    %cost = FunctionHandleConstraint( -Inf, Inf, num_decision_vars, CostFunc);
    %cost.grad_method = 'numerical';
    %prog = prog.addCost(cost);
    
    
    
    c_input_limits = BoundingBoxConstraint([deg2rad(-50); min_pitch; -Inf; -Inf; p.umin], [deg2rad(-5); max_pitch; Inf; Inf; p.umax]);
    
    prog = prog.addConstraint(c_input_limits);
    
    
    

    %c2 = BoundingBoxConstraint( [ 0.1; 10; -.5; -.5; 0 ], [1; 30; .5; .5; 4] );

    %p = p.addConstraint(c2);


    [x, objval, exitflag] = prog.solve( initial_guess );



    
    assert(exitflag == 1, ['Solver error: ' num2str(exitflag)]);

    

    %full_state = zeros(12,1);

    %full_state(5) = x(1);
    %full_state(7) = x(2);

    %p.dynamics(0, full_state, x(3:5));

    x0 = zeros(12, 1);
    x0(4) = x(1);
    x0(5) = x(2);
    x0(7) = x(3);
    x0_drake = x0;
    
    x0 = ConvertDrakeFrameToEstimatorFrame(x0);

    u0 = zeros(3,1);

    u0(1) = x(4);
    u0(2) = x(5);
    u0(3) = x(6);
    
    disp('Fixed point found:');

    disp('x0 (drake frame):')
    disp(x0_drake');

    disp('u0:')
    disp(u0');
    
    disp('xdot (drake frame):');
    xdot_temp = p.p.dynamics(0, x0_drake, u0);
    disp(xdot_temp');


    %% build lqr controller based on that trim


    % I'd like to get Q and R tuned to give something close to APM's nominal
    % PID values (omitting I since LQR can't do that)
    %
    % Roll:
    %   P: 0.4
    %   I: 0.04
    %   D: 0.02
    %
    % Pitch:
    %   P: 0.4
    %   I: 0.04
    %   D: 0.02
    %
    % Yaw:
    %   P: 1.0
    %   I: 0
    %   D: 0




    Q = diag([0 0 0 10 30 .25 0.1 .0001 0.0001 .001 .001 .1]);
    Q(1,1) = 1e-10; % ignore x-position
    Q(2,2) = 1e-10; % ignore y-position
    Q(3,3) = 1e-10; % ignore z-position


    %R = diag([35 35 35]);
    %R_values = [35 50 25];

    [A, B, C, D, xdot0, y0] = p.linearize(0, x0, u0);
    %% check linearization

    %(A*(x0-x0) + B*(u0-u0) + xdot0) - p.dynamics(0, x0, u0)

    %(A*.1*ones(12,1) + B*.1*ones(3,1) + xdot0) - p.dynamics(0, x0+.1*ones(12,1), u0+.1*ones(3,1))

    %% compte difference to PID gains K

    K_pd = zeros(3,12);

    % roll P
    K_pd(1,4) = -0.4;
    K_pd(2,4) = 0.4;

    % roll D
    K_pd(1,10) = -0.02;
    K_pd(2,10) = 0.02;

    % pitch P
    K_pd(1,5) = -0.4;
    K_pd(2,5) = -0.4;

    % pitch D
    K_pd(1,11) = -0.02;
    K_pd(2,11) = -0.02;

    %K
    %K_pd

    K_pd_yaw = K_pd;
    K_pd_aggressive_yaw = K_pd;

    K_pd_yaw(1,6) = 0.25;
    K_pd_yaw(2,6) = -0.25;

    K_pd_aggressive_yaw(1,6) = 0.5;
    K_pd_aggressive_yaw(2,6) = -0.5;


    %% add a bunch of controllers

    gains.Q = Q;
    gains.Qf = Q;
    gains.R = diag([35 35 35]);
    gains.K_pd = K_pd;
    gains.K_pd_yaw = K_pd_yaw;
    gains.K_pd_aggressive_yaw = K_pd_aggressive_yaw;


    lib = AddTiqrControllers(lib, 'tilqr-left-turn', A, B, x0, u0, gains);
end