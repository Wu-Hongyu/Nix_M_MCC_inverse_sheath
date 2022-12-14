function [ sheath_potential] = get_sheath_potential( Te )
%GET_SHEATH_POTENTIAL 此处显示有关此函数的摘要
%   此处显示详细说明
%1D PIC

%% 初始化
%clear
%close all;

%文件路径
addpath('../../packages')

% 如无说明，则单位为国际单位制
% 全局变量
constants=get_constants();% 全局常数 结构体

%--------仿真参数-----------------------------------------------------------------------------------
simulation=get_simulation('default'); %仿真参数 结构体
% 可通过取消以下代码注释来修改仿真参数

% simulation.Lx=0.01;%仿真区域长度
% simulation.num_grid_point=201;%网格格点数目
% simulation.dx=simulation.Lx/(simulation.num_grid_point-1);%空间步长
simulation.Te=Te;%e单位eV
debye=sqrt(constants.eps0*simulation.Te/(constants.e*simulation.n0));
simulation.dx=debye;
simulation.Lx=debye*(simulation.num_grid_point-1);%仿真区域长度
simulation.source_region=[0.2*simulation.Lx,0.3*simulation.Lx];
% simulation.n0=1E16;%等离子体密度

simulation.dt=0.1*2*pi/(56.41*sqrt(simulation.n0));%时间步长
simulation.end_time=60000*simulation.dt;%仿真时间总长
simulation.all_timesteps=floor(simulation.end_time/simulation.dt);%总循环次数
simulation.num0_macro_e=40000;%初始电子数目 Particle e Num
simulation.num0_macro_H=simulation.num0_macro_e;%初始离子数目Particle H Num
simulation.weight=simulation.n0*simulation.Lx/simulation.num0_macro_e;%每个宏粒子代表实际粒子的权重
% simulation.TH=1;%单位eV
% simulation.field_boundaries_type=0;%电位边界条件类型
% simulation.field_boundaries=[0,0];%电位边界条件值
veth=sqrt(constants.e*simulation.Te/constants.me);%电子温度对应的热速度
vHth=sqrt(constants.e*simulation.TH/constants.mH);%离子温度对应的热速度
%--------仿真参数-----------------------------------------------------------------------------------

%--------初始化-------------------------------------------------------------------------------------
% TODO：粒子结构体，与场结构体
%--------粒子数据
%按照Maxwell分布生成宏粒子的速度分布 x y z方向(Particle e velocity)
ve=get_v_init( veth, 'Maxwellian velocity', [simulation.num0_macro_e,3]);
vH=get_v_init( vHth, 'Maxwellian velocity', [simulation.num0_macro_H,3]);
%%初始速度分布直接规定为-dt/2时刻的值，直接开始蛙跳法

%均匀分布在空间Lx内，并给一个随机扰动
position_e=get_position_init(simulation, 'entire domain uniform+noise', [simulation.num0_macro_e,1] );
position_H=get_position_init(simulation, 'entire domain uniform+noise', [simulation.num0_macro_H,1] );

ae=zeros(simulation.num0_macro_e,3);%加速度初值 电子加速度
aH=zeros(simulation.num0_macro_H,3);%加速度初值 离子加速度
%--------场数据
[ u, A, b_extra ] = get_field_init( simulation );%离散泊松方程
rho=zeros(simulation.num_grid_point,1);%净正电荷数密度初值
E=zeros(simulation.num_grid_point+1,1);%半节点电场初值  NG-1+两个墙内的半格点
B=zeros(simulation.num_grid_point+1,1);%半节点磁场初值
%
%--------初始化--------------------------------------------------------------------------------------

% 诊断与后处理相关参数
dptime=1000;%每多少步长更新显示
avgSteps=499;%多少步长内的平均值
jj=499;
usum=0;
recordFlag=0;
u_record=zeros(simulation.num_grid_point,1);%暂时不用

log_name = get_log_init( simulation, '' );%输出初始日志
h = figure('Unit','Normalized','position',...
    [0.02 0.3 0.6 0.6]); %实时诊断使用的大窗口
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%--------主循环开始-----------------------------------------------------------------------------------

for ti=1:simulation.all_timesteps%主循环
    % for ti=1:30000%主循环
    
    % 主循环中性能考虑
    % 1. 简单代码可以inline。但同样建立函数文件，以便于test；可将test后代码复制修改。
    % 2. 使用专用函数（通过函数名而非传入参数唯一标识），注意传参耗时，不使用全局变量，
    % 尽量避免传值复制，参考 https://www.zhihu.com/question/50408548/answer/120840847
    % 3. 在package的test文件中，测试功能与性能
    
    %------推动粒子-----------------------------------------------------------------------------------------------
    % Pev=Pev+ae*dt;  %蛙跳法更新电子位置
    ve(:,1)=ve(:,1)+ae(:,1)*simulation.dt;
    position_e=position_e+ve(:,1)*simulation.dt;
    
    vH(:,1)=vH(:,1)+aH(:,1)*simulation.dt;%蛙跳法更新离子位置
    position_H=position_H+vH(:,1)*simulation.dt;
    %------推动粒子结束-----------------------------------------------------------------------------------------------
    
    %------粒子越界处理------------------------------------------------------------------------------------------------
    % TODO：待修改，作为专用函数
    %     % -------周期边界------------------------------------------------------
    %     tempFlag=(position_e<0);
    %     position_e(tempFlag)=position_e(tempFlag)+simulation.Lx;
    %     tempFlag=(position_e>simulation.Lx);
    %     position_e(tempFlag)=position_e(tempFlag)-simulation.Lx;
    
    % -------成对重注入源区 pair re-injection into source region--------------
    tempFlag=(position_e<0|position_e>simulation.Lx);
    ve(tempFlag,:)=[];%抹除超出区域的电子
    position_e(tempFlag)=[];
    
    k1=(position_H<0|position_H>simulation.Lx);%取超出范围的离子的编号
    tempsum=sum(k1);
    
    if(tempsum>0)%如果非空
        vH(k1,:)=normrnd(0,vHth,[tempsum,3]);%xyz 重注入离子速度Maxwell分布
        % 重注入粒子位置均匀随机分布在源区内
        position_H(k1)=simulation.source_region(1)+(simulation.source_region(2)-simulation.source_region(1))*rand(tempsum,1);
        temp_matrix=simulation.source_region(1)+(simulation.source_region(2)-simulation.source_region(1))*rand(tempsum,1);
        position_e=reshape([position_e; temp_matrix],[],1);%合并回原来的数组
        ve=reshape([ve; normrnd(0,veth,[tempsum,3])],[],3);
    end
    
    %--------thermalization 热化  每5步一次
    % 搭配非粒子周期边界使用
    if rem(ti,5)==1
        flag=(simulation.source_region(1)<position_e & position_e<simulation.source_region(2));
        ve(flag,:)=normrnd(0,veth,[sum(flag),3]);
    end
    %------粒子越界处理结束------------------------------------------------------------------------------------------
    
    
    
    %-----------分配电荷----------------------------------------------------------------------------------
    rhoea=zeros(simulation.num_grid_point,1);%网格左右两个点的粒子密度 电子
    rhoeb=zeros(simulation.num_grid_point,1);
    rhoaH=zeros(simulation.num_grid_point,1);%离子
    rhobH=zeros(simulation.num_grid_point,1);
    
    enearx=floor(position_e/simulation.dx)+1;%每个电子所在网格的索引 整数格点
    eassigndx=position_e-(enearx-1)*simulation.dx;%每个电子距离左边最近的网格的距离
    Eenearx=floor((position_e+0.5*simulation.dx)/simulation.dx)+1;%每个电子所在半网格的索引 半格点
    Eedx=position_e-(Eenearx*simulation.dx-3/2*simulation.dx);%每个电子距离左边最近的半网格的距离
    
    Hnearx=floor(position_H/simulation.dx)+1;
    Hassigndx=position_H-(Hnearx-1)*simulation.dx;
    EHnearx=floor((position_H+0.5*simulation.dx)/simulation.dx)+1;%每个离子所在半网格的索引 半格点
    EHdx=position_H-(EHnearx*simulation.dx-3/2*simulation.dx);
    
    for j=1:size(position_e)
        rhoea(enearx(j))=rhoea(enearx(j))+(simulation.dx-eassigndx(j));
        rhoeb(enearx(j)+1)=rhoeb(enearx(j)+1)+(eassigndx(j));
        %         rhoeb(enearx(j)+1)=rhoeb(enearx(j)+1)-e/(dx^2)*(assigndx(j))*weight;
    end
    rhoe=(rhoea+rhoeb)*(-constants.e)/(simulation.dx^2)*simulation.weight;
    %rhoP=rhoP*0;
    for j=1:size(position_H)
        rhoaH(Hnearx(j))=rhoaH(Hnearx(j))+(simulation.dx-Hassigndx(j));
        rhobH(Hnearx(j)+1)=rhobH(Hnearx(j)+1)+(Hassigndx(j));
        %         rhobH(Hnearx(j)+1)=rhobH(Hnearx(j)+1)+e/(dx^2)*(Hassigndx(j))*weight;
    end
    rhoH=(rhoaH+rhobH)*constants.e/(simulation.dx^2)*simulation.weight;
    
    rho=rhoe+rhoH;
    %-----------分配电荷结束------------------------------------------------------------
    
    %--------------求解电场---------------------------------------------------------------
    b=get_b( rho,b_extra,simulation );
    u=get_u( u,A,b,'direct inverse');
    E=get_E_at_half_node( u, simulation );
    %--------------求解电场结束---------------------------------------------------------------
    
    % TODO：待获得E_particle
    ae=-((simulation.dx-Eedx).*E(Eenearx)+Eedx.*E(Eenearx+1))*constants.e/(constants.me)/simulation.dx;
    aH=((simulation.dx-EHdx).*E(EHnearx)+EHdx.*E(EHnearx+1))*constants.e/(constants.mH)/simulation.dx;
    
    % 电压累加，为  实时后处理中取平均  做准备
    if rem(ti+jj,dptime)==1
        usum=usum+u;
        jj=jj-1;
        if jj==-1
            jj=avgSteps;
        end
    end
    
    %-----------实时诊断----------------------------------------------------------------------------------
    if rem(ti-1,dptime)==0%每隔dptime显示一次
        fprintf('当前时步数：%d \n',ti)
        
        e_num(floor(ti/dptime)+1)=size(position_e,1);%区域内的电子总量变化
        H_num(floor(ti/dptime)+1)=size(position_H,1);
        e_vAve(floor(ti/dptime)+1)=mean(abs(ve(:,1)));%x方向上的平均速率变化
        H_vAve(floor(ti/dptime)+1)=mean(abs(vH(:,1)));
        
        subplot(3,2,1);
        plot_no_versus_position( position_e,position_H,simulation );
        subplot(3,2,2);
        plot_num_versus_timestep( e_num,H_num,dptime )
        subplot(3,2,3);
        plot_2u1E_versus_x( u, ti, usum, avgSteps, E, simulation )
        subplot(3,2,4);
        plot_Ek_versus_timestep( e_vAve,H_vAve, constants.q_m_ration_e, constants.q_m_ration_H, 'e','H', dptime )
        ylabel('平均Ek [eV]'); %实际上是3倍x向平均动能
        subplot(3,2,5);%电荷分布
        plot_density_versus_x( rhoe, rhoH, rho, simulation )
        subplot(3,2,6);
        %         plot_v_versus_position( ve, vH, position_e,position_H,simulation )
        plot_vineV_versus_position( ve, vH, position_e,position_H,constants.q_m_ration_e, constants.q_m_ration_H, 'e','H', simulation )
        drawnow;
        
        usum=0; %重置
    end
    %-----------实时后处理----------------------------------------------------------------------------------
    
    if ti==50000 %稳定判据
        recordFlag=1;
    end
    if recordFlag>0 %稳定后取电压，大量时步取平均以降噪
        u_record(:,recordFlag)=u;
        recordFlag=recordFlag+1;
    end
    
end
%----主循环结束-----------------------------------------------------------------

now_str=datestr(now,'yyyy-mm-dd HH:MM:SS');
diary(log_name)
disp(now_str)
diary off

% saveas(gcf,'./others/real_time_display.png')

x_final=(0:1:200)*simulation.dx;
u_final=mean(u_record,2);
figure
plot(x_final,u_final,'-b','LineWidth',3)%多个步长电压平均值
axis([0,simulation.Lx,-inf,inf])
%         title('电势空间分布', 'FontSize', 18);

%取中间的3/5到4/5长度的电压做平均，作为鞘层电压的值。
Llimit=floor(simulation.num_grid_point*3/5);
Hlimit=floor(simulation.num_grid_point*4/5);
sheath_potential=mean(u_final(Llimit:Hlimit));

xlabel('x [m]')
ylabel('\phi [V]');
hold on;
% line([simulation.Lx-6.66e-4,simulation.Lx],[2.51,2.51],'linestyle','-.','color','r','LineWidth',3);
line([Llimit*simulation.dx,Llimit*simulation.dx],[0,max(u_final)],'linestyle','-.','color','r','LineWidth',3);
L1=legend('仿真结果','电压平均取值段');
set(L1,'location','south');
set(L1,'AutoUpdate','off');
% line([simulation.Lx-6.66e-4,simulation.Lx-6.66e-4],[0,2.51],'linestyle','-.','color','r','LineWidth',3);
line([Hlimit*simulation.dx,Hlimit*simulation.dx],[0,max(u_final)],'linestyle','-.','color','r','LineWidth',3);
% saveas(gcf,'./others/final_display.png')

% save('./others/final_data.mat')

% TODO：待修改公式，用eT替换kT
% debye=sqrt(constants.eps0*kB/constants.e/constants.e/(1e16/Te+1e16/TH))     德拜长度计算式
%
% Vf=0.5*log((2*pi*constants.me/constants.mH)*(1+TH/Te))*constants.e*Te/constants.e    等离子体电势理论值


end

