function build_variant7(p,d,r,root)
% Время измеряется в часах. Unit Delay хранит запас энергии в кВт·ч.
mdl='variant7_energy_hub';
if bdIsLoaded(mdl), close_system(mdl,0); end
load_system('simulink'); new_system(mdl);
set_param(mdl,'SolverType','Fixed-step','Solver','FixedStepDiscrete', ...
    'FixedStep',num2str(p.dt),'StopTime','24','ReturnWorkspaceOutputs','on');
% Входы: электрическая и тепловая нагрузки, солнце, тариф, сеть, газ на
% когенерацию и котёл, заряд и разряд накопителей. Конечная строка нулевая.
v=[d.e d.h r.u(:,4) d.price r.u(:,1:3) r.u(:,5:8)];
profile=[[d.t;24] [v;zeros(1,11)]];
w=get_param(mdl,'ModelWorkspace'); assignin(w,'hub_profile',profile);
add_block('simulink/Sources/From Workspace',[mdl '/Schedule'], ...
    'VariableName','hub_profile','SampleTime',num2str(p.dt),'Interpolate','off','OutputAfterFinalValue','Holding final value','Position',[25 90 130 130]);
add_block('simulink/Signal Routing/Demux',[mdl '/Flows'],'Outputs','11','Position',[175 35 180 405]);
wire('Schedule/1','Flows/1');
gain('CHP_electric',p.etaE,[260 80 350 110]); wire('Flows/6','CHP_electric/1');
gain('CHP_heat',p.etaH,[260 160 350 190]); wire('Flows/6','CHP_heat/1');
gain('Boiler_heat',p.etaBoiler,[260 210 350 240]); wire('Flows/7','Boiler_heat/1');
sumblock('Electric_balance','-++++-',[460 35 490 125]);
wire('Flows/1','Electric_balance/1'); wire('Flows/5','Electric_balance/2');
wire('Flows/3','Electric_balance/3'); wire('CHP_electric/1','Electric_balance/4');
wire('Flows/9','Electric_balance/5'); wire('Flows/8','Electric_balance/6');
sumblock('Heat_balance','-+++-',[460 160 490 250]);
wire('Flows/2','Heat_balance/1'); wire('CHP_heat/1','Heat_balance/2');
wire('Boiler_heat/1','Heat_balance/3'); wire('Flows/11','Heat_balance/4'); wire('Flows/10','Heat_balance/5');
storage('Battery',8,9,p.etaBc,p.etaBd,320);
storage('Thermal_tank',10,11,p.etaTc,p.etaTd,500);
add_block('simulink/Math Operations/Product',[mdl '/Grid_cost_rate'],'Position',[730 80 760 120]);
wire('Flows/4','Grid_cost_rate/1'); wire('Flows/5','Grid_cost_rate/2');
sumblock('Gas_total','++',[640 170 670 210]); wire('Flows/6','Gas_total/1'); wire('Flows/7','Gas_total/2');
gain('Gas_cost_rate',p.gasPrice,[720 170 810 205]); wire('Gas_total/1','Gas_cost_rate/1');
sumblock('Cost_rate','++',[865 80 895 125]); wire('Grid_cost_rate/1','Cost_rate/1'); wire('Gas_cost_rate/1','Cost_rate/2');
add_block('simulink/Signal Routing/Mux',[mdl '/Measurements'],'Inputs','6','Position',[960 70 965 360]);
wire('Electric_balance/1','Measurements/1'); wire('Heat_balance/1','Measurements/2');
wire('Battery_energy/1','Measurements/3'); wire('Thermal_tank_energy/1','Measurements/4');
wire('Cost_rate/1','Measurements/5'); wire('Flows/5','Measurements/6');
add_block('simulink/Sinks/To Workspace',[mdl '/Log'],'VariableName','hub_log','SaveFormat','Structure With Time','Position',[1030 120 1120 155]);
wire('Measurements/1','Log/1');
add_block('simulink/Sinks/Scope',[mdl '/Scope'],'Position',[1040 240 1100 285]); wire('Measurements/1','Scope/1');
% Задание русских названий блокам, чтоб без суеты.
blockLabels = {
    'Schedule', 'Суточный график';
    'Flows', 'Потоки энергии';
    'CHP_electric', 'Когенерация — электричество';
    'CHP_heat', 'Когенерация — тепло';
    'Boiler_heat', 'Газовый котёл';
    'Electric_balance', 'Электрический баланс';
    'Heat_balance', 'Тепловой баланс';
    'Grid_cost_rate', 'Затраты на электричество';
    'Gas_total', 'Суммарный расход газа';
    'Gas_cost_rate', 'Затраты на газ';
    'Cost_rate', 'Суммарные затраты в час';
    'Measurements', 'Измеряемые величины';
    'Log', 'Запись результатов';
    'Scope', 'Осциллограф';
    'Battery_charge', 'Заряд аккумулятора';
    'Battery_discharge', 'Разряд аккумулятора';
    'Battery_update', 'Изменение запаса электричества';
    'Battery_energy', 'Запас электричества';
    'Thermal_tank_charge', 'Заряд теплоаккумулятора';
    'Thermal_tank_discharge', 'Разряд теплоаккумулятора';
    'Thermal_tank_update', 'Изменение запаса тепла';
    'Thermal_tank_energy', 'Запас тепла'
};
for k=1:size(blockLabels,1)
    set_param([mdl '/' blockLabels{k,1}],'Name',blockLabels{k,2});
end
Simulink.Annotation(mdl,sprintf(['Вариант 7: газ, электричество и тепло; два накопителя\n' ...
    'Динамическая модель с заранее оптимизированным суточным графиком\n' ...
    'Время — часы; мощность — кВт; энергия — кВт·ч\n' ...
    'Запись: невязки балансов, запасы энергии, затраты в час, мощность сети']));
save_system(mdl,fullfile(root,[mdl '.slx']));
simout=sim(mdl); log=simout.get('hub_log'); y=log.signals.values;
assert(max(abs(y(:,1:2)),[],'all')<1e-6,'Нарушены балансы в Simulink');
assert(size(y,1)==size(r.E,1),'Неожиданное число отсчётов Simulink');
assert(max(abs(y(:,3:4)-r.E),[],'all')<1e-6,'Запасы энергии в Simulink и MATLAB различаются');
assert(abs(sum(y(1:end-1,5))*p.dt-r.cost)<1e-6,'Затраты в Simulink и MATLAB различаются');
save(fullfile(root,'results','simulink_validation.mat'),'log');
fprintf('Схема Simulink создана. Все проверки пройдены.\n');
open_system(mdl);
    function wire(a,b)
        add_line(mdl,a,b,'autorouting','on');
    end
    function gain(name,value,pos)
        add_block('simulink/Math Operations/Gain',[mdl '/' name],'Gain',num2str(value,17),'Position',pos);
    end
    function sumblock(name,signs,pos)
        add_block('simulink/Math Operations/Sum',[mdl '/' name],'Inputs',signs,'Position',pos);
    end
    function storage(prefix,cport,dport,etaC,etaD,y0)
        gain([prefix '_charge'],p.dt*etaC,[260 y0 355 y0+30]);
        gain([prefix '_discharge'],p.dt/etaD,[260 y0+60 355 y0+90]);
        wire(sprintf('Flows/%d',cport),[prefix '_charge/1']);
        wire(sprintf('Flows/%d',dport),[prefix '_discharge/1']);
        sumblock([prefix '_update'],'++-',[460 y0 490 y0+70]);
        add_block('simulink/Discrete/Unit Delay',[mdl '/' prefix '_energy'], ...
            'InitialCondition','0','SampleTime',num2str(p.dt),'Position',[565 y0 640 y0+40]);
        wire([prefix '_energy/1'],[prefix '_update/1']);
        wire([prefix '_charge/1'],[prefix '_update/2']);
        wire([prefix '_discharge/1'],[prefix '_update/3']);
        wire([prefix '_update/1'],[prefix '_energy/1']);
    end
end

