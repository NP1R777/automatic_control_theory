function results = run_variant7(makeModel)
if nargin < 1, makeModel = true; end
root = fileparts(mfilename('fullpath')); addpath(root);
p = hub_parameters();
n = round(24/p.dt); t = (0:n-1)'*p.dt;
d.t=t;
d.e = 90 + 25*exp(-((t-8)/2).^2) + 65*exp(-((t-19)/2.5).^2);
d.h = 115 + 55*exp(-((t-7)/2).^2) + 65*exp(-((t-20)/3).^2);
d.pv = 180*max(0,sin(pi*(t-6)/12));
d.price = 4*ones(n,1); d.price(t<7)=2; d.price(t>=17 & t<22)=9;
names = {'Separate','Integrated','Storage'};
labels = {'Раздельное снабжение','Интеграция без накопителей','С накопителями'};
for s=1:3
    results(s)=solve_case(p,d,s,names{s});
end
summary=table(string({results.name})', [results.cost]', [results.co2]', ...
    [results.gridEnergy]', [results.gasEnergy]', [results.peakGrid]', ...
    'VariableNames',{'Scenario','Cost_RUB','CO2_kg','Grid_kWh','Gas_kWh_LHV','GridPeak_kW'});
summaryRU = summary;
summaryRU.Scenario = string(labels)';
summaryRU.Properties.VariableNames = {'Сценарий','Затраты_руб','Выбросы_CO2_кг', ...
    'Энергия_из_сети_кВтч','Энергия_газа_кВтч_НТС','Пик_сети_кВт'};
disp(summaryRU);
fprintf('Экономия от интеграции: %.2f %%\n',100*(results(1).cost-results(2).cost)/results(1).cost);
fprintf('Дополнительная экономия от накопителей: %.2f %%\n',100*(results(2).cost-results(3).cost)/results(2).cost);
fprintf('Общая экономия: %.2f %%\n',100*(results(1).cost-results(3).cost)/results(1).cost);
out=fullfile(root,'results'); if ~isfolder(out), mkdir(out); end
writetable(summary,fullfile(out,'comparison.csv'));
writetable(summaryRU,fullfile(out,'comparison_RU.csv'),'Encoding','UTF-8');
save(fullfile(out,'simulation_results.mat'),'p','d','results','summary','summaryRU');
for s=1:3
    r=results(s);
    data=array2table([t d.e d.h d.pv d.price r.u r.E(1:end-1,:)], ...
        'VariableNames',{'Time_h','LoadE_kW','LoadH_kW','PV_kW','Price_RUB_kWh', ...
        'Grid_kW','CHPgas_kW','Boilergas_kW','PVused_kW','Bcharge_kW', ...
        'Bdischarge_kW','Tcharge_kW','Tdischarge_kW','Battery_kWh','Tank_kWh'});
    writetable(data,fullfile(out,[r.name '_timeseries.csv']));
    dataRU=data;
    dataRU.Properties.VariableNames={'Время_ч','Электрическая_нагрузка_кВт', ...
        'Тепловая_нагрузка_кВт','Солнечная_генерация_кВт','Тариф_руб_кВтч', ...
        'Мощность_из_сети_кВт','Газ_когенерации_кВт','Газ_котла_кВт', ...
        'Использованное_солнце_кВт','Заряд_аккумулятора_кВт','Разряд_аккумулятора_кВт', ...
        'Заряд_теплоаккумулятора_кВт','Разряд_теплоаккумулятора_кВт', ...
        'Запас_электричества_кВтч','Запас_тепла_кВтч'};
    writetable(dataRU,fullfile(out,[r.name '_timeseries_RU.csv']),'Encoding','UTF-8');
end
f=figure('Name','Вариант 7: энергетический хаб','Color','w'); tiledlayout(3,2);
nexttile; plot(t,[d.e d.h d.pv],'LineWidth',1.2); legend('Электрическая нагрузка','Тепловая нагрузка','Солнечная генерация'); ylabel('Мощность, кВт'); xlabel('Время, ч'); grid on;
nexttile; stairs(t,d.price); ylabel('Тариф, руб./кВт·ч'); xlabel('Время, ч'); grid on;
nexttile; plot(t,[results(1).u(:,1) results(2).u(:,1) results(3).u(:,1)]); legend(labels); ylabel('Мощность из сети, кВт'); xlabel('Время, ч'); grid on;
nexttile; stairs([t;24],results(3).E); legend('Аккумулятор','Теплоаккумулятор'); ylabel('Запас энергии, кВт·ч'); xlabel('Время, ч'); grid on;
nexttile; bar(1:3,[results.cost]); xticks(1:3); xticklabels(labels); ylabel('Затраты за сутки, руб.'); grid on;
nexttile; bar(1:3,[results.co2]); xticks(1:3); xticklabels(labels); ylabel('Выбросы CO_2 за сутки, кг'); grid on;
axs=findall(f,'Type','axes');
for ax=axs', ax.Toolbar.Visible='off'; end
drawnow;
exportgraphics(f,fullfile(out,'comparison.png'),'Resolution',160);
if makeModel
    if license('test','Simulink')
        build_variant7(p,d,results(3),root);
    else
        warning('Simulink недоступен: расчёт MATLAB и результаты готовы.');
    end
end
end

function p=hub_parameters()
p.dt=0.25; % часы; мощности в кВт, запасы энергии в кВт·ч
p.etaE=0.35; p.etaH=0.45; p.etaBoiler=0.90;
p.chpElectricMax=140;
p.etaBc=0.95; p.etaBd=0.95; p.etaTc=0.95; p.etaTd=0.95;
p.Bmax=200; p.Tmax=400; p.Bstep=20; p.Tstep=40;
p.Bpower=100; p.Tpower=200;
p.gasPrice=0.65; % руб./кВт·ч по НТС: условная цена газа
p.gridCO2=0.45; p.gasCO2=0.202; % кг/кВт·ч; условные коэффициенты эксплуатационных выбросов
end

function r=solve_case(p,d,scenario,name)
n=numel(d.t);
if scenario==3
    [eb,et]=ndgrid(0:p.Bstep:p.Bmax,0:p.Tstep:p.Tmax);
    states=[eb(:),et(:)];
else
    states=[0 0];
end
m=size(states,1); deltaB=states(:,1)'-states(:,1);
deltaT=states(:,2)'-states(:,2);
bc=max(deltaB,0)/(p.dt*p.etaBc); bd=max(-deltaB,0)*p.etaBd/p.dt;
tc=max(deltaT,0)/(p.dt*p.etaTc); td=max(-deltaT,0)*p.etaTd/p.dt;
valid=bc<=p.Bpower+1e-9 & bd<=p.Bpower+1e-9 & tc<=p.Tpower+1e-9 & td<=p.Tpower+1e-9;
% Начальные и конечные запасы равны нулю: бесплатная начальная энергия исключена.
V=inf(m,1); V(1)=0; policy=zeros(n,m);
for k=n:-1:1
    [stage,~,~,~,~]=dispatch(d.e(k)+bc-bd,d.h(k)+tc-td,d.pv(k),d.price(k),p,scenario);
    stage(~valid)=inf;
    [V,bestNext]=min(stage*p.dt+V',[],2); policy(k,:)=bestNext';
end
assert(isfinite(V(1)),'Не найден допустимый режим');
optimum=V(1); idx=1; E=zeros(n+1,2); u=zeros(n,8);
for k=1:n
    j=policy(k,idx);
    [~,g,f,b,pv]=dispatch(d.e(k)+bc(idx,j)-bd(idx,j),d.h(k)+tc(idx,j)-td(idx,j),d.pv(k),d.price(k),p,scenario);
    u(k,:)=[g f b pv bc(idx,j) bd(idx,j) tc(idx,j) td(idx,j)];
    E(k+1,:)=states(j,:); idx=j;
end
resE=u(:,1)+u(:,4)+p.etaE*u(:,2)+u(:,6)-d.e-u(:,5);
resH=p.etaH*u(:,2)+p.etaBoiler*u(:,3)+u(:,8)-d.h-u(:,7);
resB=diff(E(:,1))-p.dt*(p.etaBc*u(:,5)-u(:,6)/p.etaBd);
resT=diff(E(:,2))-p.dt*(p.etaTc*u(:,7)-u(:,8)/p.etaTd);
assert(max(abs([resE;resH;resB;resT]))<1e-7,'Нарушен энергетический баланс');
assert(all(u(:)>=-1e-8),'Обнаружен отрицательный поток');
assert(max(abs(E(end,:)))<1e-8,'Конечный запас энергии не равен нулю');
assert(all(u(:,5).*u(:,6)<1e-8) && all(u(:,7).*u(:,8)<1e-8),'Обнаружены одновременные заряд и разряд');
r.name=name; r.u=u; r.E=E;
r.cost=sum(d.price.*u(:,1)+p.gasPrice*(u(:,2)+u(:,3)))*p.dt;
assert(abs(r.cost-optimum)<1e-6,'Восстановленное решение не совпадает с результатом оптимизации');
r.co2=sum(p.gridCO2*u(:,1)+p.gasCO2*(u(:,2)+u(:,3)))*p.dt;
r.gridEnergy=sum(u(:,1))*p.dt; r.gasEnergy=sum(u(:,2)+u(:,3))*p.dt;
r.peakGrid=max(u(:,1)); r.balanceError=max(abs([resE;resH;resB;resT]));
end

function [cost,grid,gas,boiler,pvUsed]=dispatch(e,h,pv,price,p,scenario)
% Минимизация текущих затрат для каждого перехода между состояниями накопителей.
% Тепло когенерации используется полностью. Экспорт запрещён. Солнце можно ограничивать.
feasible=e>=-1e-8 & h>=-1e-8; e=max(e,0); h=max(h,0);
cap=min(p.chpElectricMax/p.etaE,min(e/p.etaE,h/p.etaH));
if scenario==1, cap=zeros(size(e)); end
kink=min(cap,max(0,(e-pv)/p.etaE));
cost=inf(size(e)); gas=zeros(size(e));
for candidate=1:3
    if candidate==1, f=zeros(size(e)); elseif candidate==2, f=cap; else, f=kink; end
    g=max(0,e-pv-p.etaE*f); b=max(0,h-p.etaH*f)/p.etaBoiler;
    c=price*g+p.gasPrice*(f+b);
    better=c<cost; cost(better)=c(better); gas(better)=f(better);
end
grid=max(0,e-pv-p.etaE*gas); boiler=max(0,h-p.etaH*gas)/p.etaBoiler;
pvUsed=min(pv,max(0,e-p.etaE*gas)); cost(~feasible)=inf;
end


