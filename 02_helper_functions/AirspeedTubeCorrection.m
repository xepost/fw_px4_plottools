function [dp_raw, dp_filtered, airspeed_indicated, airspeed_true,...
    airspeed_true_unfiltered] = AirspeedTubeCorrection(sysvector, D, L)
% Correct the airspeed and differential pressure based on the pressure loss
% in the pitot tube

eps_raw = CalculateDifferentialPressureCorrectionFactor(...
    sysvector('differential_pressure.differential_pressure_raw').Data,...
    sysvector('differential_pressure.temperature').Data, D, L);
eps_filtered = CalculateDifferentialPressureCorrectionFactor(...
    sysvector('differential_pressure.differential_pressure_filtered').Data,...
    sysvector('differential_pressure.temperature').Data, D, L);

% correct dp
dp_raw = timeseries(sysvector('differential_pressure.differential_pressure_raw').Data./(1 + eps_raw), ...
    sysvector('differential_pressure.differential_pressure_raw').Time);
dp_filtered = timeseries(sysvector('differential_pressure.differential_pressure_filtered').Data./(1 + eps_filtered),...
    sysvector('differential_pressure.differential_pressure_filtered').Time);

% compute indicated airspeed
airspeed_indicated = timeseries(sqrt(2.0*abs(dp_filtered.Data) / 1.225), dp_filtered.Time);
airspeed_indicated_unfiltered = timeseries(sqrt(2.0*abs(dp_raw.Data) / 1.225), dp_raw.Time);

% resample the indicated airspeed
if (airspeed_indicated.Time(1) > sysvector('airspeed.indicated_airspeed').Time(1))
    airspeed_indicated = airspeed_indicated.addsample('Data', airspeed_indicated.Data(1),...
        'Time', sysvector('airspeed.indicated_airspeed').Time(1));
    airspeed_indicated_unfiltered = airspeed_indicated_unfiltered.addsample('Data', airspeed_indicated_unfiltered.Data(1),...
        'Time', sysvector('airspeed.indicated_airspeed').Time(1));
end
if (airspeed_indicated.Time(end) < sysvector('airspeed.indicated_airspeed').Time(end))
    airspeed_indicated = airspeed_indicated.addsample('Data', airspeed_indicated.Data(end),...
        'Time', sysvector('airspeed.indicated_airspeed').Time(end));
    airspeed_indicated_unfiltered = airspeed_indicated_unfiltered.addsample('Data', airspeed_indicated_unfiltered.Data(end),...
        'Time', sysvector('airspeed.indicated_airspeed').Time(end));
end
airspeed_indicated = resample(airspeed_indicated, sysvector('airspeed.indicated_airspeed').Time);
airspeed_indicated_unfiltered = resample(airspeed_indicated_unfiltered, sysvector('airspeed.indicated_airspeed').Time);

% hack for the factor from indicated airspeed to true airspeed until we log
% the baro pressure
airspeed_true = timeseries(airspeed_indicated.Data ./ sysvector('airspeed.indicated_airspeed').Data .*...
    sysvector('airspeed.true_airspeed').Data, airspeed_indicated.Time);
airspeed_true_unfiltered = timeseries(airspeed_indicated_unfiltered.Data ./ sysvector('airspeed.indicated_airspeed').Data .*...
    sysvector('airspeed.true_airspeed').Data, airspeed_indicated_unfiltered.Time);