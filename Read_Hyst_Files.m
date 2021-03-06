function [Specimen_Names, Data, Specimen_Masses, Data_Order] = Read_Hyst_Files(path, files, file_type)
%
% Function that reads and processes the hysteresis files
%
% Input:
%       path - the path to the files
%       files - the files to be loaded
%       file_type - a flag to indicate the type of machine used to measure
%                   the data
%                   1 - MicroMag VSM/AGM
%                   2 - Quantum Designs MPMS
%                   3 - VFTB
%                   4 - Lake Shore VSMs
%                   5 - MagIC
%                   6 - MicroSense VSM
%
% Output:
%       Specimen_Names - The names of the loaded specimens
%       Data - Cell arrray of the loop data
%       Specimen_Masses - Specimen masses
%       Data_Order - Flag for the measurement order
%                    1 - Positive to negative fields
%                    -1 - Negative to positive fields

% TODO - Add reads for dates and timestamps for future MagIC proofing
%

%% Inital processing

% Define the MicroMag file versions that are supported
% Legacy format has a single, comma delimited, header line with no labels
% Modern format has multiple, labeled, header lines
% NOTE: Legacy version -1, and 0 carry no version number, the version
% number read is actually reading the configuration (i.e., VSM or AGM)
MicroMag_Legacy_Support = [-1, 0, 6, 8, 9];
MicroMag_Modern_Support = [16.002, 16, 15];


% The number of files
nfiles=length(files);

% Preallocate some data
Specimen_Names = cell(nfiles, 1);
Data = cell(nfiles, 1);
Specimen_Masses = NaN(nfiles, 1);
Data_Order = NaN(nfiles, 1);

%% Loop through the files
for ii = 1:1:nfiles
    
    %% Process the name
    
    name = regexp(files{ii}, '\.', 'split');
    
    if length(name) == 1
        % The file has no dot-extension
        Specimen_Names(ii) = {name};
    else
        
        % Check if we can use strjoin
        try
            name = strjoin(name(1:end-1), '.'); % rejoin with any extra periods
        catch
            tmp_name = name{1};
            for jj= 2: length(name(1:end-1))
                tmp_name = [tmp_name, '.', name{jj}]; %#ok<AGROW>
            end
            name = tmp_name;
        end
        
        Specimen_Names(ii) = {name};
        
    end
        
    %% Read the files
    FID = fopen(strcat(path, files{ii}),'r');
    
    switch file_type
        
        case 1 % Princeton MicroMag VSM/AGM
            
            
            % Get the file version
            Line1 = fgetl(FID);
            
            % Close and reopen to reset the file read
            fclose(FID);
            
            % Line1 changes from version to version - sigh!
            LineSplit = regexp(Line1, ' ', 'split');
            
            switch LineSplit{2}
                
                case '2900/3900'
                    % Modern style
                    Old_File_Flag = 0;
                case '2900'
                    % Old style
                    Old_File_Flag = 1;
                otherwise
                    error('Read_Hyst_Files:MicroMagFormat', '%s is an unrecognized MicroMag file version: %s', name, files{ii});
                    
            end
            
            % Check for the old file format flag
            % This is needed as some file version numbers are the same for
            % old and modern file formats
            if Old_File_Flag == 1
                
                % Reopen the file and reader the header line
                FID = fopen(strcat(path, files{ii}),'r');
                
                Line1 = fgetl(FID);
                
                Header = regexp(Line1, ',', 'split');
                
                File_Ver = str2double(Header{2});
                
                if ~any(File_Ver == MicroMag_Legacy_Support)
                    keyboard
                    error('Read_Hyst_Files:MicroMagFormat', '%s is an unrecognized MicroMag file version: %d', name, File_Ver);
                end
                
                input = textscan(FID, '%f,%f%*[^\n]');
                
                Fields = input{1,1};
                Moments = input{1,2};
                
                % Get info from the header
                switch File_Ver
                    case 0
                        
                        Units = Header{27};
                        Mass = 1e6 * str2double(Header{22}); % Convert to mg
                        
                    case {6, 8, 9}
                        
                        Units = Header{30};
                        Mass = 1e6 * str2double(Header{25}); % Convert to mg
                        
                    otherwise
                        error('Read_Hyst_Files:MicroMagFormat', 'Should not be here. Error should throw before.')
                        
                end
                
                % check for missing mass data
                if Mass == 0 || isnan(Mass)
                    Mass = NaN;
                end
                
                
                % Do a unit check and conversion
                % Moments are Am^2
                % Fields are mT
                switch Units
                    case '0'
                        % cgs units
                        
                        % Oe to mT
                        Fields = Fields./10;
                        
                        % emu to Am^2
                        Moments = Moments./1e3;
                        
                    case '1'
                        % SI units
                        
                        % A/m to mT
                        Fields = Fields .* (4*pi)/1e4;
                        
                    case '2'
                        % Hybrid SI units
                        
                        % T to mT
                        Fields = Fields.*1e3;
                        
                    otherwise
                        error('Read_Hyst_Files:Units', '%s is not a recognized unit system. Complain to Greig.', Units);
                end
                
                
            else
                % Modern style data file
                
                % Open up the file again
                FID = fopen(strcat(path, files{ii}),'r');
                
                
                % Get the first line, which contains the file version number
                tline = fgetl(FID);
                File_Ver = cell2mat(textscan(tline, '%*s %*s %*s %*s %*s %f%*s\n'));
                
                % Do a version support check
                if ~any(File_Ver == MicroMag_Modern_Support)
                    error('Read_Hyst_Files:MicroMag',...
                        'This MicroMag file version is not yet supported. Complain to Greig. Version %f', File_Ver);
                end
                
                nLines = 1; % line counter for debugging
                
                while ischar(tline)
                    
                    tline = fgetl(FID);
                    nLines = nLines + 1;
                    
                    if isempty(tline)
                        
                        continue;
                        
                    elseif ~ischar(tline)
                        
                        % Reached the end of the file
                        break;
                        
                    elseif regexpi(tline, 'Units of measure') == 1
                        
                        Units = textscan(tline, '%*s%*s%*s%s');
                        Units = char(Units{1});
                        
                    elseif regexpi(tline, 'Mass') == 1
                        
                        Mass = textscan(tline, '%*s%f');
                        
                        if isempty(Mass{1}) || double(Mass{1}) == 0
                            Mass = NaN;
                        else
                            Mass = 1e6 * double(Mass{1}); % Convert to mg
                        end
                        
                    elseif regexpi(tline, 'Hysteresis loop?') == 1
                        
                        Measure_Loop = textscan(tline, '%*s%*s%s');
                        
                        if strcmpi(Measure_Loop{1}, 'No') == 1
                            warning('Read_Hyst_Files:NoMeasurement', '%s has no measured loop, skipping', name);
                        end
                        
                    elseif regexpi(tline, 'Initial magnetization?') == 1
                        
                        Initial_Mag = textscan(tline, '%*s%*s%s');
                        Initial_Mag = char(Initial_Mag{1});
                        
                    elseif regexpi(tline, 'Number of segments') == 1
                        
                        nSeg = textscan(tline, '%*s%*s%*s%d');
                        nSeg = nSeg{1};
                        
                    elseif regexpi(tline, 'Segment') == 1
                        % At the start of the segment script
                        break;
                    end
                    
                end % while ischar(tline)
                
                
                % Version check for the header lines on the script
                if any(File_Ver==[16.002 16])
                    nHeader_seg = 2;
                elseif any(File_Ver == 15)
                    nHeader_seg = 1;
                else
                    error('Read_Hyst_Files:MicroMag', 'Should not be here! WAH!!')
                end
                
                % Read the lines to skip them
                for jj = 1:nHeader_seg
                    tline = fgetl(FID); %#ok<NASGU>
                    nLines = nLines + 1;
                end
                
                % Read the measurement script
                nCol = 7; % Number of columns in the script
                Script = cell(nSeg, nCol);
                for jj = 1:nSeg
                    tline = fgetl(FID);
                    nLines = nLines + 1;
                    Script(jj,:) = regexp(tline, ',', 'split');
                end
                
                
                % Version check for the header lines on the data
                if any(File_Ver == [16.002 16])
                    nHeader_Data = 4;
                elseif any(File_Ver == 15 )
                    nHeader_Data = 3;
                else
                    error('Read_Hyst_Files:MicroMag',...
                        'This MicroMag file version is not yet supported. Complain to Greig. Version %f', File_Ver);
                end
                
                % Read the lines to skip them
                for jj = 1:nHeader_Data
                    tline = fgetl(FID); %#ok<NASGU>
                    nLines = nLines + 1;
                end
                
                % check for other non-hysteresis measurements and skip
                % Can be done more efficiently
                if strcmpi(Initial_Mag, 'yes')
                    nSkip = str2double(Script{1,end});
                    
                    Initial_Mag_Data = textscan(FID, '%f,%f%*[^\n]', nSkip); %#ok<NASGU>
                end
                
                input = textscan(FID, '%f,%f%*[^\n]');
                
                Fields = input{1,1};
                Moments = input{1,2};
                
                % Do a unit check and conversion
                % Moments are Am^2
                % Fields are mT
                switch Units
                    
                    case 'SI'
                        
                        % A/m to mT
                        Fields = Fields .* (4*pi)/1e4;
                        
                    case 'Hybrid'
                        
                        % T to mT
                        Fields = Fields.*1e3;
                        
                    case 'cgs'
                        
                        % Oe to mT
                        Fields = Fields./10;
                        
                        % emu to Am^2
                        Moments = Moments./1e3;
                        
                    otherwise
                        error('Read_Hyst_Files:Units', '%s is not a recognized unit system. Complain to Greig.', Units);
                end
                
                
            end
            
            
        case 2 % Quantum Designs MPMS
            
            % Get the first line,
            tline = fgetl(FID);
            
            nLines = 1; % line counter for debugging
            
            while ischar(tline)
                
                tline = fgetl(FID);
                nLines = nLines + 1;
                
                if isempty(tline)
                    continue;
                elseif ~ischar(tline)
                    % Reached the end of the file
                    break;
                    
                elseif regexpi(tline, 'INFO, WEIGHT') == 1
                    
                    Mass = textscan(tline, '%*s %*s %f');
                    
                    if isempty(Mass{1}) || double(Mass{1}) == 0
                        Mass = NaN;
                    else
                        Mass = double(Mass{1}); % Assumed to be in mg
                    end
                    
                elseif regexpi(tline, '\[Data]') == 1
                    % Reached the data
                    break;
                end
                
            end
            
            
            % Read the data header
            tline = fgetl(FID);
            
            input = [];
            
            while ischar(tline)
                tline = fgetl(FID);
                
                if ~ischar(tline)
                    % reached the end of the file
                    break;
                end
                
                input = [input; regexp(tline, ',', 'split')]; %#ok<AGROW>
                
            end
            
            % Get the fields and moments
            Fields = cellfun(@str2double, input(:,3));
            Moments = cellfun(@str2double, input(:,5));
            
            % Convert units
            
            % Oe to mT
            Fields = Fields./10;
            
            % emu to Am^2
            Moments = Moments./1e3;
            
            
        case 3 % VFTB
            
            % Get the first header line
            header1 = fgetl(FID);
            
            % Skipp a couple of lines
            fgetl(FID);
            fgetl(FID);
            
            % Get the column header line and the data
            header2 = fgetl(FID);
            input = textscan(FID, '%f\t%f\t%f\t%f\t%f');
            
            
            % Process the first header - contains mass
            S = strtrim(regexpi(header1, 'weight:', 'split'));
            S = textscan(S{2}, '%f %s');
            
            % Get the mass in mg
            switch S{2}{1}
                
                case 'mg'
                    Mass = S{1};
                case 'g'
                    Mass = S{1}/1e3;
                case 'kg'
                    Mass = S{1}/1e6;
                otherwise
                    error('Read_Hyst_Files:VFTB_Mass', 'Unrecognized mass units: %s.', S{2}{1});
            end
            
            % Get the column headers
            S = strtrim(regexp(header2, '\t', 'split'));
            
            % Find the indices of the fields and moments/magnetizations
            for jj=1:length(S);
                
                if strcmpi(S{jj}(1:5), 'field')
                    Field_idx = jj;
                end
                
                if strcmpi(S{jj}(1:3), 'mag')
                    Moment_idx = jj;
                end
                
            end
            
            % Get the fields and field units and convert to mT
            S2 = strtrim(regexp(S{Field_idx}, '/', 'split'));
            
            switch S2{2}
                case 'mT'
                    Fields = input{Field_idx};
                case 'T'
                    Fields = input{Field_idx}./1e3;
                case 'Oe'
                    Fields = input{Field_idx}./10;
                otherwise
                    error('Read_Hyst_Files:VFTB_Field', 'Unrecognized field units: %s.', S{2}{1});
            end
            
            
            % Get the moments and moment units
            S2 = strtrim(regexp(S{Moment_idx}, '/', 'split'));
            
            Moments = input{Moment_idx};
            
            if length(S2) == 3
                % We have mass normalization (convert magnetization to moment)
                switch S2{3}
                    case 'mg'
                        Moments = Moments .* Mass;
                    case 'g'
                        Moments = Moments .* (Mass/1e3);
                    case 'kg'
                        Moments = Moments .* (Mass/1e6);
                    otherwise
                        error('Read_Hyst_Files:VFTB_Magnetization', 'Unrecognized Magnetization units: %s per %s.', S2{2}, S2{3});
                end
                
            end
            
            % Check the moment units and convert to Am2
            switch S2{2}
                case 'emu'
                    Moments = Moments ./ 1e3;
                otherwise
                    error('Read_Hyst_Files:VFTB_Moment', 'Unrecognized moment units: %s.', S2{2});
            end
            
            % The VFTB records the inital moment acquisition
            % Remove this by finding the first step where the fields decrease
            dF = diff(Fields);
            ddF = diff(sign(dF));

            switch sum(ddF~=0)
                
                case 0
                    % All fields are the same
                    error('Read_Hyst_Files:VFTB', 'All fields are idetical. Please please check data file %s.', files{ii});
                    
                case 1
                    % All is good - do nothing
                    
                case 2
                    % We have 3 segments
                    % Assume we have intial moment curve
                    
                    idx = find(ddF~=0); % indices of sign change
                    
                    % Get the intial curve
                    Initial_Mag_Data = [Fields(1:idx(1)), Moments(1:idx(1))]; %#ok<NASGU>
                    
                    % Remove inital curve
                    Fields(1:idx(1)) = [];
                    Moments(1:idx(1)) =[];
                    
                otherwise
                    error('Read_Hyst_Files:VFTB', 'Unrecognized measurement sequence. Please contact the authors.');
            end
            
            
        case 4 % Lake Shore
            
            % Get the first to test version
            Line1 = fgetl(FID);
            
            % Close and reopen to reset the file read
            fclose(FID);
            
            % Line1 changes from version to version - sigh!
            LineSplit = regexp(Line1, ' ', 'split');
            
            switch LineSplit{1}
                
                case '#RUN'
                    % Mass may not be recorded
                    Mass = NaN;
                    
                    % Reopen the file and reader the header line
                    FID = fopen(strcat(path, files{ii}),'r');
                    
                    % Get the first line,
                    tline = fgetl(FID);
                    nLines = 1;
                    
                    while ischar(tline)
                        
                        tline = fgetl(FID);
                        nLines = nLines + 1;
                        
                        Initial_Flag = 0;
                        
                        if isempty(tline)
                            continue;
                        elseif ~ischar(tline)
                            % Reached the end of the file
                            break;
                            
                        elseif regexpi(tline, 'Include Initial Curve:') == 1
                            
                            S = strsplit(tline, ': ');
                            
                            switch S{2}
                                case 'FALSE'
                                    Initial_Flag = 0;
                                case 'TRUE'
                                    Initial_Flag = 1;
                            end
                            
                        elseif regexpi(tline, '##DATA TABLE') == 1
                            % reached the data
                            break;
                        end
                        
                    end
                    
                    % Get the header and split it
                    header = fgetl(FID);
                    header = regexp(header, ',', 'split');
                    
                    Field_idx = find(cellfun(@(x) ~isempty(x), regexpi(header, 'Field [')));
                    Moment_idx = find(cellfun(@(x) ~isempty(x), regexpi(header, 'Moment [')));
                    Seg_idx = find(cellfun(@(x) ~isempty(x), regexpi(header, 'Segment')));
                    
                    if isempty(Field_idx) || isempty(Moment_idx)
                        error('Read_Hyst_Files:LakeShore', 'Lake Shore IDEAS VSM format not recognized.');
                    end
                    
                    % Get the units
                    Field_Units = (regexpi(header{Field_idx}, '\[(\w*)\]', 'tokens'));
                    Field_Units = char(Field_Units{1});
                    
                    Moment_Units = (regexpi(header{Moment_idx}, '\[(\w*)\]', 'tokens'));
                    Moment_Units = char(Moment_Units{1});
                    
                    
                    input = [];
                    
                    while ischar(tline)
                        tline = fgetl(FID);
                        
                        if ~ischar(tline)
                            % reached the end of the file
                            break;
                        elseif isempty(tline)
                            continue;
                        end
                        
                        input = [input; regexp(tline, ',', 'split')]; %#ok<AGROW>
                        
                    end
                    
                    
                    % Get the fields and moments
                    Fields = cellfun(@str2double, input(:,Field_idx));
                    Moments = cellfun(@str2double, input(:,Moment_idx));
                    Segments = cellfun(@str2double, input(:,Seg_idx));  %#ok<FNDSB>
                    
                    
                    % Convert Field units
                    switch Field_Units
                        
                        case 'mT'
                            % All sorted - do nothing
                        case 'T'
                            Fields = Fields./1e3;
                        case 'Oe'
                            Fields = Fields./10;
                        case 'G'
                            Fields = Fields./10;
                        otherwise
                            error('Read_Hyst_Files:IDEAS_VSM_Field', 'Unrecognized field units: %s.', Field_Units);
                    end
                    
                    % Convert Moment units
                    switch Moment_Units
                        case 'emu'
                            Moments = Moments ./ 1e3;
                        otherwise
                            error('Read_Hyst_Files:IDEAS_VSM_Moment', 'Unrecognized moment units: %s.', Moment_Units);
                    end
                    
                    
                    
                    if Initial_Flag == 1
                        uSeg = unique(Segments);
                        
                        if length(uSeg) ~= 3
                            error('Read_Hyst_Files:LakeShore_8600', 'Unexpected initial magnetization data sequence.');
                        end
                        
                        % Get the number of the inital curve segment
                        Seg_num = Segments(1);
                        
                        % Remove
                        Initial_Mag_Data = [Fields(Segments==Seg_num), Moments(Segments==Seg_num)]; %#ok<NASGU>
                        
                        Fields(Segments==Seg_num) =[];
                        Moments(Segments==Seg_num) = [];
                        
                    end
                    
                    %                     keyboard
                    
                case 'Start' % IDEAS VSM
                    
                    % Reopen the file and reader the header line
                    FID = fopen(strcat(path, files{ii}),'r');
                    
                    % Get the first line,
                    tline = fgetl(FID);
                    nLines = 1;
                    
                    while ischar(tline)
                        
                        tline = fgetl(FID);
                        nLines = nLines + 1;
                        
                        if isempty(tline)
                            continue;
                        elseif ~ischar(tline)
                            % Reached the end of the file
                            break;
                        elseif regexpi(tline, '***DATA***') == 1
                            % reached the data
                            break;
                        end
                        
                    end
                    
                    
                    % Reloop to avoid unknown numbers of blank lines
                    while ischar(tline)
                        
                        tline = fgetl(FID);
                        nLines = nLines + 1;
                        
                        if isempty(tline)
                            continue;
                        elseif ~ischar(tline)
                            % Reached the end of the file
                            break;
                        elseif regexpi(tline, 'FIELD') == 1
                            % reached the data
                            break;
                        end
                        
                    end
                    
                    % Read the header to get the data indices
                    header = regexp(tline, '\t', 'split');
                    Field_idx = find(cellfun(@(x) ~isempty(x), regexpi(header, 'Field')));
                    Moment_idx = find(cellfun(@(x) ~isempty(x), regexpi(header, 'Moment')));
                    
                    
                    if isempty(Field_idx) || isempty(Moment_idx)
                        error('Read_Hyst_Files:LakeShore', 'Lake Shore IDEAS VSM format not recognized.');
                    end
                    
                    % Get the units
                    Field_Units = (regexpi(header{Field_idx}, '\((\w*)\)', 'tokens'));
                    Field_Units = char(Field_Units{1});
                    
                    Moment_Units = (regexpi(header{Moment_idx}, '\((\w*)\)', 'tokens'));
                    
                    if isempty(Moment_Units)
                        % SI units with funny ^2 character
                        if strcmp(header{Moment_idx}(9:11), 'A m')
                            Moment_Units = 'Am2';
                        else
                            error('Read_Hyst_Files:IDEAS_VSM_Moment_Units', 'Error reading the moment units from %s.', files{ii});
                        end
                        
                    else
                        Moment_Units = char(Moment_Units{1});
                    end
                    
                    
                    % Read the data
                    input = textscan(FID, '%f %f');
                    
                    % Convert Field units
                    switch Field_Units
                        
                        case 'mT'
                            Fields = input{Field_idx};
                        case 'T'
                            Fields = input{Field_idx}.*1e3;
                        case 'Oe'
                            Fields = input{Field_idx}./10;
                        case 'G'
                            Fields = input{Field_idx}./10;
                        otherwise
                            error('Read_Hyst_Files:IDEAS_VSM_Field', 'Unrecognized field units: %s.', Field_Units);
                    end
                    
                    % Convert Moment units
                    switch Moment_Units
                        case 'emu'
                            Moments = input{Moment_idx} ./ 1e3;
                        case 'Am2'
                            Moments = input{Moment_idx};
                        otherwise
                            error('Read_Hyst_Files:IDEAS_VSM_Moment', 'Unrecognized moment units: %s.', Moment_Units);
                    end
                    
                    
                    % Process the data to check for inital moment
                    dF = diff(Fields);
                    ddF = diff(sign(dF));
                    
                    switch sum(ddF~=0)
                        
                        case 0
                            % All fields are the same
                            error('Read_Hyst_Files:IDEAS_VSM_Measurement', 'All fields are idetical. Please please check data file %s.', files{ii});
                            
                        case 1
                            % All is good - do nothing
                            
                        case 2
                            % We have 3 segments
                            % Assume we have intial moment curve
                            
                            idx = find(ddF~=0); % indices of sign change
                            
                            % Get the intial curve
                            Initial_Mag_Data = [Fields(1:idx(1)), Moments(1:idx(1))]; %#ok<NASGU>
                            
                            % Remove inital curve
                            Fields(1:idx(1)) = [];
                            Moments(1:idx(1)) =[];
                            
                        otherwise
                            error('Read_Hyst_Files:IDEAS_VSM_Measurement', 'Unrecognized measurement sequence. Please contact the authors.');
                    end
                    
                    
                    % Check the rest of the file for mass
                    tline = fgetl(FID);
                    
                    Mass = NaN;
                    
                    while ischar(tline)
                        
                        if isempty(tline)
                            %                     disp('empty')
                            continue;
                        elseif ~ischar(tline)
                            % Reached the end of the file
                            %                              M
                            break;
                            
                        elseif regexpi(tline, 'Mass') == 1
                            Mass_line = textscan(tline, '%*s %f %s');
                            
                            Mass_Units = Mass_line{1,2}{1};
                            
                            switch Mass_Units
                                
                                case 'mg'
                                    Mass = Mass_line{1};
                                    
                                case 'g'
                                    Mass = Mass_line{1} .* 1e3;
                                    
                                case 'kg'
                                    Mass = Mass_line{1} .* 1e6;
                                    
                                otherwise
                                    error('Read_Hyst_Files:IDEAS_VSM_Mass', 'Unrecognized Mass units: %s.', Mass_Units);
                                    
                            end
                            
                        end
                        
                        tline = fgetl(FID);
                        
                    end
                    
                    %                 case ''
                    %                     warndlg([{'Full output of Lake Shore data files is not currently supported.'};...
                    %                     {'Please contact Greig Paterson for assistance.'}], 'Format not supported');
                    %
                    %                      Mass = NaN;
                    
                otherwise
                    error('Read_Hyst_Files:Lakeshore', 'Unrecognized Lake Shore format.');
                    
            end
            
            
        case 5 % MagIC
            % TODO - Read MagIC files
            
            
        case 6 % MicroSense VSM
            
            % Mass is not recorded in the data file
            Mass = NaN;
            
            % Get the first line,
            tline = fgetl(FID);
            
            nLines = 1; % line counter for debugging
            nCol = 0; % number of data colums
            fmt = '';
            Moment_idx = [];
            Field_idx = [];
            Moment_Units = '';
            Field_Units = '';
            
            while ischar(tline)
                
                tline = fgetl(FID);
                nLines = nLines + 1;
                
                if isempty(tline)
                    continue;
                elseif ~ischar(tline)
                    % Reached the end of the file
                    break;
                    
                elseif regexpi(tline, 'Column') == 1
                    nCol = nCol + 1;
                    
                    fmt = strcat(fmt, ' %f');
                    
                    if isempty(Field_idx)
                        tmp_idx = regexpi(tline, ': Applied Field');
                        if ~isempty(tmp_idx)
                            Field_idx = nCol;
                            Field_Units = regexp(tline, '\[(\w+)\]', 'tokens');
                            Field_Units = char(Field_Units{1});
                        end
                    end
                    
                    if isempty(Moment_idx)
                        tmp_idx = regexpi(tline, ': Raw Signal Mx');
                        if ~isempty(tmp_idx)
                            Moment_idx = nCol;
                            Moment_Units = regexp(tline, '\[(\w+)\]', 'tokens');
                            Moment_Units = char(Moment_Units{1});
                        end
                    end
                    
                    
                elseif regexpi(tline, '@Date: ') == 1
                    
                    tmp_idx1 = regexpi(tline, '(');
                    tmp_idx2 = regexpi(tline, ')');
                    Date = tline(tmp_idx1+1:tmp_idx2-1); %#ok<NASGU>
                    
                elseif regexpi(tline, '@Time: ') == 1
                    Time = tline(8:end); %#ok<NASGU>
                    
                elseif regexpi(tline, '@@Data') == 1
                    % Reached the data
                    break;
                end
                
            end
            
            % Read the data header
            input = textscan(FID, fmt, 'HeaderLines', 1);
            
            % Convert Field units
            switch Field_Units
                
                case 'mT'
                    Fields = input{Field_idx};
                case 'T'
                    Fields = input{Field_idx}.*1e3;
                case 'Oe'
                    Fields = input{Field_idx}./10;
                case 'G'
                    Fields = input{Field_idx}./10;
                otherwise
                    error('Read_Hyst_Files:MicroSense_VSM_Field', 'Unrecognized field units: %s.', Field_Units);
            end
            
            % Convert Moment units
            switch Moment_Units
                case 'emu'
                    Moments = input{Moment_idx} ./ 1e3;
                case 'memu'
                    Moments = input{Moment_idx}./1e6;
                case 'Am2'
                    Moments = input{Moment_idx};
                otherwise
                    error('Read_Hyst_Files:MicroSense_VSM_Moment', 'Unrecognized moment units: %s.', Moment_Units);
            end
            
            
        otherwise
            error('Read_Hyst_Files:File_Type', 'The file type flag is unrecognized');
    end
    
    % Close the file
    fclose(FID);
    
    % Data order flag
    if Fields(1) < 0
        Data_Order(ii) = -1;
    else
        Data_Order(ii) = 1;
    end
    
    % Get the cell with all the data
    Data(ii) = {[Fields, Moments]};

    Specimen_Masses(ii) = Mass;
        
end

% Clear some key variables
clear vars tline File_Ver Units Mass Measure_Loop Initial_Mag nSeg Initial_Mag_Data Fields Moments


end