% This Matlab Script can be used to import the binary logged values of the
% PX4FMU into data that can be plotted and analyzed.

%% ************************************************************************
% logconv: Main function
% ************************************************************************
function logconv()
% Clear everything
clc;
clear all;
close all;
path(path,'01_draw_functions');
path(path,'01_draw_functions/01_subfunctions');
path(path,'02_helper_functions');
path(path,'02_helper_functions/01_topics_mapping');
path(path,'03_kmltoolbox_v2.6');
path(path,'04_log_files');
path(path,'05_csv_files');
path(path,'06_mat_files');
path(path,'07_kmz_files');

% ************************************************************************
% SETTINGS (modify necessary parameter)
% ************************************************************************

% set the path to your log file here file here
fileName = 'log001.ulg';

% the source from which the data is imported
% 0: converting the ulog to csv files and then parsing the csv files
%    (required for the first run)
% 1: only parsing the pre-existing csv files
%    (requires the generated csv files)
% 2: import the data from the .mat file
%    (requires the generated .mat file)
% else: Defaults to 0
loadingMode = 0;

% setting for the topic mapping
% 0: mapping for the latest master
% 1: mapping for the 1.65 release
% 2: mapping for the master at 2017.11.22
topicMapping = 0;

% Print information while converting/loading the log file in mode 0 or 1.
% Helpfull to identify field missmatchs.
loadingVerbose = false;

% indicates if the sysvector map and the topics struct should be saved
% after they are generated.
saveMatlabData = true;

% delete the csv file after a run of the script
deleteCSVFiles = true;

% id of the vehicle (note displaying the logs multiple vehicles at the same
% time is not supported yet)
vehicleID = 0;

% delimiter for the path
%   '/' for ubuntu
%   '\' for windows
pathDelimiter = '/';

% indicates if the plots should be generated. If set to false the log file
% is only converted to the sysvector.
generatePlots = true;

% only plot the logged data from t_start to t_end. If both are set to 0.0
% all the logged data is plotted.
t_start = 0.0;
t_end = 0.0;

% change topic names or add new topics in the setupTopics function.

% ************************************************************************
% SETTINGS end
% ************************************************************************

% ******************
% Import the data
% ******************

% get the file name without the file ending
plainFileName = char(extractBefore(fileName,'.'));

% conversion factors
fconv_timestamp=1E-6;    % [microseconds] to [seconds]
fconv_gpsalt=1E-3;       % [mm] to [m]
fconv_gpslatlong=1E-7;   % [gps_raw_position_unit] to [deg]

if loadingMode==2
    if exist([plainFileName '.mat'], 'file') == 2
        load([plainFileName '.mat']);
        if (numel(fieldnames(topics)) == 0) || (sysvector.Count == 0)
            error(['Sysvector and/or topics loaded from the .mat file are empty.' newline ...
                'Run script first with loadingMode=0 and saveMatlabData=true'])
        end
    else
        error(['Could not load the data as the file does not exist.' newline ...
            'Run script first with loadingMode=0 and saveMatlabData=true'])
    end
else
    % setup the topics which could have been logged
    switch topicMapping
        case 0
            topics = setupTopicsMaster();
        case 1
            topics = setupTopicsV1p65();
        case 2
            topics = setupTopics20171122();
        otherwise
            error('Invalid topicMapping value')
    end
    
    % import the data
    sysvector = containers.Map();
    ImportPX4LogData();
end

% ******************
% Crop the data
% ******************
sysvector_keys = sysvector.keys';
CropPX4LogData();

% ******************
% Print the data
% ******************

if generatePlots
    DisplayPX4LogData(sysvector, topics, plainFileName, fconv_gpsalt, fconv_gpslatlong)
end


%% ************************************************************************
%  *** END OF MAIN SCRIPT ***
%  NESTED FUNCTION DEFINTIONS FROM HERE ON
%  ************************************************************************

%% ************************************************************************
%  ImportPX4LogData (nested function)
%  ************************************************************************
%  Import the data from the log file.

function ImportPX4LogData()
    disp('INFO: Start importing the log data.')
    
    if exist(fileName, 'file') ~= 2
        error('Log file does not exist.')
    end

    % *********************************
    % convert the log file to csv files
    % *********************************
    if (loadingMode~=1) && (loadingMode~=2)
        tic;
        system(sprintf('ulog2csv 04_log_files%s%s -o 05_csv_files', pathDelimiter, fileName));
        time_csv_conversion = toc;
        disp(['INFO: Converting the ulog file to csv took ' char(num2str(time_csv_conversion)) ' s.'])
    end
    
    % *********************************
    % unpack the csv files
    % *********************************
    disp('INFO: Starting to import the csv data into matlab.')
    tic;
    topic_fields = fieldnames(topics);
    
    if numel(topic_fields) == 0
        error('No topics specified in the setupTopics() function.') 
    end
    
    force_debug = false;
    for idx_topics = 1:numel(topic_fields)
        csv_file = ...
            [plainFileName '_' topics.(topic_fields{idx_topics}).topic_name...
            '_' char(num2str(vehicleID)) '.csv'];
        if exist(csv_file, 'file') == 2
            try
                csv_data = tdfread(csv_file, ',');
                csv_fields = fieldnames(csv_data);
                
                if ((numel(fieldnames(csv_data))-1) ~= numel(topics.(topic_fields{idx_topics}).fields))
                    disp(['The number of data fields in the csv file is not equal to' ...
                        ' the ones specified in the topics struct for '...
                        topic_fields{idx_topics} '. Check that the mapping is correct']);
                    force_debug = true;
                end

                for idx = 2:numel(csv_fields)
                    ts = timeseries(csv_data.(csv_fields{idx}), ...
                        csv_data.timestamp*fconv_timestamp, ...
                        'Name', [topic_fields{idx_topics} '.' char(topics.(topic_fields{idx_topics}).fields(idx-1))]);
                    ts.DataInfo.Interpolation = tsdata.interpolation('zoh');
                    sysvector([topic_fields{idx_topics} '.' char(topics.(topic_fields{idx_topics}).fields(idx-1))]) = ts;

                    if loadingVerbose || force_debug
                        str = sprintf('%s \t\t\t %s',...
                            topics.(topic_fields{idx_topics}).fields(idx-1),...
                            string(csv_fields{idx}));
                        disp(str)
                    end
                end

                topics.(topic_fields{idx_topics}).logged = true;
            catch
                disp(['Could not process the topic: ' char(topic_fields{idx_topics})]);
            end
        end
        force_debug = false;
    end
    
    % manually add a value for the commander state with the timestamp of
    % the latest global position estimate as they are used together
    if topics.commander_state.logged && topics.vehicle_global_position.logged
       ts_temp = append(sysvector('commander_state.main_state'),...
           timeseries(sysvector('commander_state.main_state').Data(end),...
           sysvector('vehicle_global_position.lon').Time(end)));
       ts_temp.DataInfo.Interpolation = tsdata.interpolation('zoh');
       ts_temp.Name = 'commander_state.main_state';
       sysvector('commander_state.main_state') = ts_temp;
    end

    time_csv_import = toc;
    disp(['INFO: Importing the csv data to matlab took ' char(num2str(time_csv_import)) ' s.'])

    % check that we have a nonempy sysvector
    if (loadingMode~=1) && (loadingMode~=2)
        if sysvector.Count == 0
            error(['Empty sysvector: Converted the ulog file to csv and parsed it.' newline ...
                'Contains the logfile any topic specified in the setupTopics() function?'])
        end
    else
        if sysvector.Count == 0
            error(['Empty sysvector: Tried to read directly from the csv files.' newline ...
                'Does any csv file for a topic specified the setupTopics() function exist?'])
        end
    end
    
    % *********************************
    % remove duplicate timestamps
    % *********************************
    sysvec_keys = sysvector.keys;
    for idx_key = 1:numel(sysvec_keys)
        % copy data info
        data_info = sysvector(sysvec_keys{idx_key}).DataInfo;
                
        % remove duplicate timestamps
        [~,idx_unique,~] = unique(sysvector(sysvec_keys{idx_key}).Time,'legacy');
        ts_temp = getsamples(sysvector(sysvec_keys{idx_key}), idx_unique);

        ts_temp.DataInfo = data_info;
        sysvector(sysvec_keys{idx_key}) = ts_temp;
    end
   
    % *********************************
    % save the sysvector and topics struct if requested
    % *********************************
    if saveMatlabData
        save(['06_mat_files' pathDelimiter plainFileName '.mat'], 'sysvector', 'topics');
    end
    
    % *********************************
    % delete the csv files if requested
    % *********************************
    if deleteCSVFiles
        system(sprintf('rm 05_csv_files%s%s_*', pathDelimiter, plainFileName));
    end
    
    disp('INFO: Finished importing the log data.')
end


%% ************************************************************************
%  CropPX4LogData (nested function)
%  ************************************************************************
%  Import the data from the log file.

function CropPX4LogData()
    if (t_start == 0.0 && t_end == 0.0)
        disp('INFO: Not cropping the logging data.')
        return;
    end
    if (t_start > t_end)
        disp('INFO: t_start > t_end: not cropping the logging data.')
        return;
    end
    
    disp('INFO: Start cropping the log data.')
    
    for idx_key = 1:numel(sysvector_keys)
        % copy data info
        data_info = sysvector(sysvector_keys{idx_key}).DataInfo;
        
        % crop time series
        ts_temp = getsampleusingtime(sysvector(sysvector_keys{idx_key}), t_start, t_end);
        ts_temp.DataInfo = data_info;
        sysvector(sysvector_keys{idx_key}) = ts_temp;
    end
    
    disp('INFO: Finshed cropping the log data.')
end

end
