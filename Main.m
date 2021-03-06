clc; clear all; close all;
% 5G mmWave Positioning and Mapping
% (c) Hyowon Kim, 2019 (Ph.D. student at Hanyang Univerisy, Seoul, South Korea, emai: khw870511@hanyang.ac.kr)
% Usage: this code generates vehicle state estimation and environment mapping


%% System parameters
para.MC = 10; % # Monte Carlo run
para.TIME = 40; % # time evolution (para.TIME = 2*pi/Vel_rot.ini/para.t_du)
rng(1)
for mc = 1:para.MC
    loadpath = ['measurement/measurement_' num2str(mc) '_' num2str(para.TIME)]; % load vehicular network
    load(loadpath)

    % result generation selection (1-on; 0-off)
    EvalTimeOn = 1; % performance over time 1-on; 0-off
    EvalMCOn = 1; % average performance 1-on; 0-off
    Video_PHD = 1; % making video for each map PHD
    para.particle_PDF = 1; % making the particle PDF of 1-D vehicle state
    para.error_check = 1; % showing the state estimation error in real-time
    
    F_up_PHD = 0; % figure for the update map PHD 1-on; 0-off
    F_ave_PHD = 0; % figure for the average map PHD 1-on; 0-off
    F_UL_PHD = 0; % figure for the UL map PHD 1-on; 0-off
    Video_FusionMap=0; % making video for fused map PHD
    
    % simulation mode selection
    para.onlyLOS = 1; % 1) using only LoS path; 2) with all paths
    if para.onlyLOS == 1
        MapFusionMode = 1; %% when only LOS path is utilized, there are no map fusion.
    else
        MapFusionMode = 3; % 1) without map fusion; 2) map fusion per vehicle and uplink transmission to the BS; 3) as well as downlink transmission to the vehicle
    end
    para.BiasHeadingKnown = 0; % 1) Bias and heading are known
    para.HeadingKnown = 0; % 1) Heading is known
    para.prior_error = 2;
    
    % simulation parameter setting
    para.UECovInitial = diag([.3 .3 0 0.3*pi/180 0 0 .3].^2); % vehicle state prior covariance
    para.N_p = 2000; % # of particlces
    measurementCovariance = 9*measurementCovariance; % tunning parameter for map update
    para.BS_cov = 1e-2; %initial cov of BS position diag([cov cov])
    para.birth_weight = 1.5*1e-5; % birth weight; considering clutter intensity; the sum of birth PHDs is not necessary to be 1.
    para.r_UC = 1; % when the FoV gradually deacrease near the FoV, the uncertain distance r_{UC} is set to 1 m.
    
    para.P_D = 0.9; % Detection probability
    para.c_z = para.lambda*(1/200)*(1/2/pi)^2*(1/pi)^2; % clutter intensity; 1.2832e-05  auumed to be constant (1/R_max, 1/R, 1/2pi)
    
    % pruning and mering
    para.pruning_T = 1e-4; % truncating threshold T, which should be bigger than (1-P_d)/(3#sources) (ref. Ba-Ngu et al., ``GM PHD filter,'' IEEE TSP, 2006.)
    para.pruning_U = 7^2; % terging threshold U, Mahalnobis dist = sqrt(U) (ref. Ba-Ngu et al., ``GM PHD filter,'' IEEE TSP, 2006.)
    para.pruning_J = 50; % maximum allowable number of Gaussians J_max (ref. Ba-Ngu et al., ``GM PHD filter,'' IEEE TSP, 2006.)
    para.pruning_COV = 50; % if the unceratinty of a map is larger than 50 [m^2], then the map is ignored.
    
    % map fusion
    para.ULTD = 4;
    Fusion_v1 = 10:para.ULTD:para.TIME; % map fusion time index for the vehicle 1
    Fusion_v2 = 12:para.ULTD:para.TIME; % map fusion time index for the vehicle 2
    
    % mapping result
    para.TargetDetectionThr_VA = 0.7; % weight threshold for VA detection
    para.TargetDetectionThr_SP = 0.55; % weight threshold for SP detection
    
    % grid for map PHD generation
    para.xx=-220:5:220;
    para.yy=-220:5:220;
    [para.X,para.Y] = meshgrid(para.xx,para.yy);
    para.X_grid = para.X(:); para.Y_grid = para.Y(:);
    
    %% PHD filter and map fusion
    Stack =[];
    for ti = 1:para.TIME
        tic
        if ti == 1
            % initial particle generation
            for i = 1:para.N_vehicle 
                [up_UE(i), up_Map(i), UL_Map, V_Est(:,i)]  = IniMapUE(para, state(:,ti,i), BS);
                Stack(ti).up_Map(i) =up_Map(i); Stack(ti).up_UE(i) = up_UE(i); Stack(ti).V_Est(:,i) = V_Est(:,i); ave_Map(i) = up_Map(i);
            end
        else
            
            % downlink map transmission
            % MapFusionMode 1) 1) without map fusion; 2) map fusion per vehicle and uplink transmission to the BS; 3) as well as downlink transmission to the vehicle
            % MapFusionOnOff 1) vehicle 1 map fusion; 2) vehicle2 map fusion; 3) no fusion
            if ti >=3
                % no downlink map transmission
                if MapFusionMode == 1 || MapFusionMode == 2 || UpMapTrans == 3 
                    
                % downlink map transmission
                elseif MapFusionMode == 3 
                    for i = 1:para.N_vehicle
                        if i == UpMapTrans
                            up_Map(i) = DLMapCopy(UL_Map, para); % BS sends map back to the corresponding vehicle
                        else
                            up_Map(i) = up_Map(i); % Another vehicle does not communicate with the BS
                        end
                    end
                end
            end
            
            % prediction (Map and UE)
            for i = 1:para.N_vehicle
                [prediction_UE(i),prediction_Map(i), Birth(i)] = PredMapUE(up_UE(i),up_Map(i),para,state(:,ti,i),Channel.Visible.TOT(:,ti,i),Channel.Clutter(ti).vehicle(i),BS,v(i).Time(ti).measurement,measurementCovariance);
            end
            % correction (Map and UE)
            for i = 1:para.N_vehicle
                [up_Map(i), up_UE(i), V_Est(:,i)] = CorrMapUE(F_up_PHD,prediction_UE(i),prediction_Map(i),Birth(i),para,state(:,ti,i),Channel.Visible.TOT(:,ti,i),BS,VA,SP,v(i).Time(ti).measurement,Channel.Clutter(ti).vehicle(i),measurementCovariance,i,ti,MapFusionMode,mc);
                Stack(ti).V_Est(:,i) = V_Est(:,i); Stack(ti).up_UE(i) = up_UE(i); Stack(ti).up_Map(i) = up_Map(i); Stack(ti).prediction_Map(i) = prediction_Map(i);
            end
            % average map determination (= weighted sum of particle maps)
            for i = 1:para.N_vehicle
                [ave_Map(i), ave_PHD(i)] = AveMap(F_ave_PHD, up_UE(i), up_Map(i), para, state(:,ti,i), V_Est(:,i), BS, VA, SP, i, ti);
                Stack(ti).ave_Map(i) = ave_Map(i); Stack(ti).ave_PHD(i) = ave_PHD(i);
            end
            
            % uplink transmission and map fusion (From vehicle to BS) 
            if MapFusionMode == 2 || MapFusionMode == 3
                if numel(intersect(Fusion_v1,ti)) == 1 % 10:4:para.TIME;
                    i = 1; UpMapTrans = 1; % vehicle 1 sends the map to the BS
                elseif numel(intersect(Fusion_v2,ti)) == 1% 12:4:para.TIME; for vehicle 2
                    i = 2; UpMapTrans = 2; % vehicle 2 sends the map to the BS
                else
                    UpMapTrans = 3; % No uplink transmission
                end
                % Vehicle 1 and 2 resectively send the averaged map to the BS at ti = 10:4:40 and 12:4:40, respectively. Then, the BS performs the map fusion
                if UpMapTrans == 1 || UpMapTrans == 2 
                    [UL_Map,PriorPHD,UpdatePHD,FusionPHD] = ULMapFusion(F_UL_PHD, Stack, UL_Map, up_UE(i), ave_Map(i), para, state(:,ti,i), BS, VA, SP, i, ti);
                    Stack(ti).UL_Map = UL_Map; Stack(ti).PriorPHD = PriorPHD; Stack(ti).UpdatePHD = UpdatePHD; Stack(ti).FusionPHD = FusionPHD;
                else % 
                end
            end
            
            % particle resampling
            for i = 1:para.N_vehicle
                up_UE(i) = Resampling(up_UE(i), V_Est(:,i), state(:,ti,i), para);
            end
            if para.onlyLOS ~= 1
            % debugging mode (real-time detected VA)
                for i = 1:para.N_vehicle
                    ind_VA = find(ave_Map(i).ST(2).P(1).weight(:)>para.TargetDetectionThr_VA);
                    sprintf('time %d, vehicle %d # detected VA is %d', ti, i, numel(ind_VA))
                    if numel(ind_VA) ~=4 && ti >=3
                        sprintf('Error occur in mapping parts, time %d, vehicle %d # detected VA is %d', ti, i, numel(ind_VA))
                        ind_VA;
                    end
                end
            end
        end
        sprintf('time %d/%d, Monte Carlo %d/%d', ti, para.TIME, mc, para.MC)
        toc
    end
    
    %-------------------------- performance evaluation --------------------------
    if EvalTimeOn == 1
        Perform(mc) = PerformTime(VA, SP, para, MapFusionMode, state, Stack, mc);
    end
    % making video
    if Video_PHD == 1 && para.onlyLOS ~= 1
        VideoAvePHD(Stack, BS, VA, SP, state, para, Channel.Clutter, MapFusionMode, mc);
    end
    if Video_FusionMap == 1 && MapFusionMode ~= 1
        VideoFusionPHD(Stack, BS, VA, SP, state,para, MapFusionMode, mc);
    end
    % Data save
    sp = sprintf('save/M%d_T%d_V%d_FM%d_P%d',mc,para.TIME,para.N_vehicle,MapFusionMode,para.N_p);
    save(sp);
end
% averaged performance
if EvalMCOn == 1
    PerformMC(para, MapFusionMode, Perform);
end
