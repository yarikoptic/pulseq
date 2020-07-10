% this is a demo low-performance EPI sequence
% which doesn"t use ramp-samping. It is only good for educational purposes
%
% 
close all
clear all
tic
seq=mr.Sequence();              % Create a new sequence object
fov=220e-3; Nx=64; Ny=64;       % Define FOV and resolution
thickness=3e-3;                 % slice thinckness
Nslices=2;
Nsegs = 0;
Nreps = 3;
Navigator = 3;

% Set system limits
lims = mr.opts('MaxGrad',32,'GradUnit','mT/m',...
               'MaxSlew',130,'SlewUnit','T/m/s', ...
               'rfRingdownTime', 30e-6, 'rfDeadTime', 100e-6);


% Create 90 degree slice selection pulse and gradient
[rf, gz] = mr.makeSincPulse(pi/2,'system',lims,'Duration',3e-3,...
    'SliceThickness',thickness,'apodization',0.5,'timeBwProduct',4);

% define the trigger to play out
trig=mr.makeTrigger('physio1','duration', 2000e-6); % duration after

% Define other gradients and ADC events
deltak=1/fov;
kWidth = Nx*deltak;
dwellTime = 4e-6; % I want it to be divisible by 2
readoutTime = Nx*dwellTime;
flatTime=ceil(readoutTime*1e5)*1e-5; % round-up to the gradient raster
gx = mr.makeTrapezoid('x',lims,'Amplitude',kWidth/readoutTime,'FlatTime',flatTime);
adc = mr.makeAdc(Nx,'Duration',readoutTime,'Delay',gx.riseTime+flatTime/2-(readoutTime-dwellTime)/2);
nrlabel = mr.makeLabel('SET','REP', 0);
nsllabel = mr.makeLabel('SET','SLC', 0);
setseglabel = mr.makeLabel('SET','SEG', 1);
nseglabel = mr.makeLabel('SET','SEG', 0);
setavglabel = mr.makeLabel('SET','AVG',1);
navglabel = mr.makeLabel('SET','AVG',0);
nllabel = mr.makeLabel('SET','LIN', 0);
centllabel = mr.makeLabel('SET','LIN', round(Ny/2));

crlabel = mr.makeLabel('INC','REP', 1);
csllabel = mr.makeLabel('INC','SLC', 1);
cllabel = mr.makeLabel('INC','LIN', 1);
setnavlabel = mr.makeLabel('SET','NAV',1);
unsetnavlabel = mr.makeLabel('SET','NAV', 0);

% Pre-phasing gradients
preTime=8e-4;
gxPre = mr.makeTrapezoid('x',lims,'Area',-gx.area/2,'Duration',preTime); % removed -deltak/2 to aligh the echo between the samples
gzReph = mr.makeTrapezoid('z',lims,'Area',-gz.area/2,'Duration',preTime);
gyPre = mr.makeTrapezoid('y',lims,'Area',-Ny/2*deltak,'Duration',preTime);

% Phase blip in shortest possible time
dur = ceil(2*sqrt(deltak/lims.maxSlew)/10e-6)*10e-6;
gy = mr.makeTrapezoid('y',lims,'Area',deltak,'Duration',dur);

% Define sequence blocks
seq.addBlock(nrlabel,nsllabel,nseglabel,nllabel); %rep/slc/seg/line reset
for r=1:Nreps
    seq.addBlock(trig,nsllabel,nseglabel,nllabel); %slc/seg/line reset
    for s=1:Nslices
        rf.freqOffset=gz.amplitude*thickness*(s-1-(Nslices-1)/2);
        seq.addBlock(rf,gz,nllabel);   %lin reset
        seq.addBlock(gxPre,gzReph);
        for n=1:Navigator
            if (n == 1)
               seq.addBlock(gx,adc,setnavlabel,setseglabel,centllabel);
            elseif (n == 3)
               seq.addBlock(gx,adc,setseglabel,centllabel,setavglabel);
            else
               seq.addBlock(gx,adc,nseglabel,centllabel);
            end
            gx.amplitude = -gx.amplitude; 
        end
        %seq.addBlock(gxPre,gyPre,gzReph);
        seq.addBlock(gyPre,nllabel,unsetnavlabel,navglabel);%lin/avg reset
        gx.amplitude = -gx.amplitude;  
        for i=1:Ny
            gx.amplitude = -gx.amplitude;   % Reverse polarity of read gradient
            if rem(i,2)
                seq.addBlock(nseglabel);
            else
                seq.addBlock(setseglabel);                
            end
            seq.addBlock(gx,adc);   % Read one line of k-space
            seq.addBlock(gy,cllabel);               % Phase blip
        end
        seq.addBlock(csllabel)
    end
    seq.addBlock(crlabel);
end
    
seq.write('epi_label.seq');   % Output sequence for scanner
toc
%seq.plot();             % Plot sequence waveforms
seq.plot('TimeRange',[0 0.03], 'TimeDisp', 'ms', 'label', 'lin');
% new single-function call for trajectory calculation
[ktraj_adc, ktraj, t_excitation, t_refocusing, t_adc] = seq.calculateKspace();

% plot k-spaces
time_axis=(1:(size(ktraj,2)))*lims.gradRasterTime;
figure; plot(time_axis, ktraj'); % plot the entire k-space trajectory
hold; plot(t_adc,ktraj_adc(1,:),'.'); % and sampling points on the kx-axis
figure; plot(ktraj(1,:),ktraj(2,:),'b'); % a 2D plot
axis('equal'); % enforce aspect ratio for the correct trajectory display
hold; plot(ktraj_adc(1,:),ktraj_adc(2,:),'r.');

% seq.sound(); % simulate the seq's tone
seq.read('epi_label.seq');
seq.write('epi_label2.seq');