function result = analyze_pq_signal_fft_q15(dataFile, fs, f0)
%ANALYZE_PQ_SIGNAL_FFT_Q15 Analyze FFT results of exported Q1.15 PQ signals.
%   result = analyze_pq_signal_fft_q15()
%       Select a CSV file exported by generate_pq_signal_q15 and analyze it.
%
%   result = analyze_pq_signal_fft_q15(dataFile)
%       Analyze the specified CSV file. The script tries to read fs and f0
%       from the matching pq_signal_q15_config_*.txt file.
%
%   result = analyze_pq_signal_fft_q15(dataFile, fs, f0)
%       Analyze the specified CSV file using the given sampling rate and
%       fundamental frequency.

    if nargin < 1 || isempty(dataFile)
        [name, folder] = uigetfile('*.csv', 'Select exported Q15 CSV file');
        if isequal(name, 0)
            result = [];
            return;
        end
        dataFile = fullfile(folder, name);
    end

    if nargin < 2
        fs = [];
    end
    if nargin < 3
        f0 = [];
    end

    cfg = readMatchingConfig(dataFile);
    if isempty(fs) && isfield(cfg, 'fs')
        fs = cfg.fs;
    end
    if isempty(f0) && isfield(cfg, 'f0')
        f0 = cfg.f0;
    end
    if isempty(fs) || ~isfinite(fs) || fs <= 0
        answer = inputdlg('Sampling frequency fs / Hz:', 'FFT analysis parameter', 1, {'200000'});
        if isempty(answer)
            result = [];
            return;
        end
        fs = str2double(answer{1});
    end
    if isempty(f0) || ~isfinite(f0) || f0 <= 0
        answer = inputdlg('Fundamental frequency f0 / Hz:', 'FFT analysis parameter', 1, {'50'});
        if isempty(answer)
            result = [];
            return;
        end
        f0 = str2double(answer{1});
    end
    validateattributes(fs, {'numeric'}, {'scalar', 'finite', 'positive'}, mfilename, 'fs');
    validateattributes(f0, {'numeric'}, {'scalar', 'finite', 'positive'}, mfilename, 'f0');

    data = readtable(dataFile);
    signals = pickSignals(data);
    if isempty(signals)
        error('No supported Q15 signal columns were found in %s.', dataFile);
    end

    maxOrder = max(1, min(50, floor((fs / 2) / f0)));
    orders = (1:maxOrder).';
    result = struct();
    result.dataFile = dataFile;
    result.fs = fs;
    result.f0 = f0;
    result.config = cfg;
    result.signals = struct([]);

    fig = figure('Name', 'Q1.15 waveform Fourier analysis', ...
        'NumberTitle', 'off', 'Color', 'w');
    tiledlayout(fig, numel(signals), 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    for k = 1:numel(signals)
        x = signals(k).value(:);
        n = numel(x);
        t = (0:n-1).' / fs;
        [freq, mag, phaseDeg] = singleSidedFft(x, fs);
        harmonic = harmonicTable(freq, mag, phaseDeg, f0, orders);

        result.signals(k).name = signals(k).name;
        result.signals(k).time = t;
        result.signals(k).value = x;
        result.signals(k).freq = freq;
        result.signals(k).magnitude = mag;
        result.signals(k).phase_deg = phaseDeg;
        result.signals(k).harmonic = harmonic;

        plotTime(nexttile, t, x, signals(k).name);
        plotSpectrum(nexttile, freq, mag, f0, maxOrder, signals(k).name);

        fprintf('\n%s\n', signals(k).name);
        disp(harmonic);
    end

    if numel(signals) >= 2
        result.phaseDifference = compareSignalPhase(result.signals(1).harmonic, result.signals(2).harmonic);
        fprintf('\nPhase difference: %s - %s\n', signals(2).name, signals(1).name);
        disp(result.phaseDifference);
    end
end

function cfg = readMatchingConfig(dataFile)
    cfg = struct();
    [folder, name] = fileparts(dataFile);
    token = regexp(name, 'pq_signal_q15_data_(\d{8}_\d{6})', 'tokens', 'once');
    if isempty(token)
        return;
    end

    cfgFile = fullfile(folder, ['pq_signal_q15_config_' token{1} '.txt']);
    if ~isfile(cfgFile)
        return;
    end

    lines = readlines(cfgFile);
    for i = 1:numel(lines)
        line = strtrim(lines(i));
        parts = regexp(line, '^([A-Za-z0-9_]+)=(.+)$', 'tokens', 'once');
        if isempty(parts)
            continue;
        end
        value = str2double(parts{2});
        if ~isnan(value)
            cfg.(parts{1}) = value;
        end
    end
end

function signals = pickSignals(data)
    names = data.Properties.VariableNames;
    signals = struct('name', {}, 'value', {});

    if any(strcmp(names, 'Signal1_Q15_Value'))
        signals(end+1).name = 'Signal 1 Q15';
        signals(end).value = data.Signal1_Q15_Value;
    elseif any(strcmp(names, 'Q15_Value'))
        signals(end+1).name = 'Signal 1 Q15';
        signals(end).value = data.Q15_Value;
    elseif any(strcmp(names, 'FloatSignal'))
        signals(end+1).name = 'Signal 1 Float';
        signals(end).value = data.FloatSignal;
    end

    if any(strcmp(names, 'Signal2_Q15_Value'))
        signals(end+1).name = 'Signal 2 Q15';
        signals(end).value = data.Signal2_Q15_Value;
    elseif any(strcmp(names, 'Signal2_Float'))
        signals(end+1).name = 'Signal 2 Float';
        signals(end).value = data.Signal2_Float;
    end
end

function [freq, mag, phaseDeg] = singleSidedFft(x, fs)
    n = numel(x);
    x = x - mean(x, 'omitnan');
    nfft = 2^nextpow2(n);
    X = fft(x, nfft) / n;
    halfCount = nfft / 2 + 1;
    X = X(1:halfCount);
    freq = fs * (0:halfCount-1).' / nfft;
    mag = abs(X);
    if halfCount > 2
        mag(2:end-1) = 2 * mag(2:end-1);
    end
    phaseDeg = angle(X) * 180 / pi;
end

function tbl = harmonicTable(freq, mag, phaseDeg, f0, orders)
    targetFreq = orders * f0;
    amp = zeros(size(orders));
    phase = zeros(size(orders));
    actualFreq = zeros(size(orders));

    for i = 1:numel(orders)
        [~, idx] = min(abs(freq - targetFreq(i)));
        actualFreq(i) = freq(idx);
        amp(i) = mag(idx);
        phase(i) = phaseDeg(idx);
    end

    fundamentalAmp = max(amp(1), eps);
    ampPercent = 100 * amp / fundamentalAmp;
    thdPercent = 100 * sqrt(sum(amp(2:end).^2)) / fundamentalAmp;
    thdColumn = nan(size(orders));
    thdColumn(1) = thdPercent;

    tbl = table(orders, targetFreq, actualFreq, amp, ampPercent, phase, thdColumn, ...
        'VariableNames', {'Order', 'TargetFreq_Hz', 'ActualFreq_Hz', ...
        'Amplitude', 'AmplitudePercentOfFundamental', 'Phase_deg', 'THD_percent'});
end

function phaseDiff = compareSignalPhase(h1, h2)
    commonCount = min(height(h1), height(h2));
    orders = h1.Order(1:commonCount);
    diffDeg = wrapDegrees(h2.Phase_deg(1:commonCount) - h1.Phase_deg(1:commonCount));
    phaseDiff = table(orders, diffDeg, 'VariableNames', {'Order', 'Signal2MinusSignal1_deg'});
end

function deg = wrapDegrees(deg)
    deg = mod(deg + 180, 360) - 180;
end

function plotTime(ax, t, x, signalName)
    maxPoints = min(numel(t), 6000);
    idx = round(linspace(1, numel(t), maxPoints));
    plot(ax, t(idx), x(idx), 'LineWidth', 1.0);
    grid(ax, 'on');
    xlabel(ax, 'Time / s');
    ylabel(ax, 'Amplitude');
    title(ax, [signalName ' time domain']);
end

function plotSpectrum(ax, freq, mag, f0, maxOrder, signalName)
    freqMax = min(freq(end), f0 * (maxOrder + 1));
    mask = freq <= freqMax;
    stem(ax, freq(mask), mag(mask), 'Marker', 'none');
    grid(ax, 'on');
    xlabel(ax, 'Frequency / Hz');
    ylabel(ax, 'Amplitude');
    title(ax, [signalName ' spectrum']);
    xlim(ax, [0, freqMax]);
end
