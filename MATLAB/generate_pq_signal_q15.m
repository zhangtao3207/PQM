function generate_pq_signal_q15
% 电能质量监测模拟信号生成工具
% 生成 50 Hz 基波 + 2~50 次可配置谐波 + 随机噪声，并转换为 Q1.15 补码数据。
%
% 推荐默认参数：
%   fs = 200000 Hz，保持 200 kSPS 采样率。
%   n  = 8192 = 2^13。200 kSPS 下读取两个 50 Hz 基波周期至少需要 8000 点，
%        取 8192 点既能覆盖两个完整周期，又便于 FFT、缓存和 FPGA 数据处理。
%
% 谐波幅值比例说明：
%   2~50 次谐波的比例和始终保持为 1。
%   某一项被修改后，程序会根据该项相对上一次的变化量自动调整其他项。
%   最终某次谐波实际幅值 = 基波幅值 * 整体谐波强度倍率 * 该次谐波比例。

    app = struct();
    app.defaultOutputDir = fileparts(mfilename('fullpath'));
    app.orders = 2:50;
    app.visibleRows = 7;
    app.scrollTop = 1;
    app.enableSecondSignal = false;
    app.secondIndependent = false;
    app.editingSecond = false;
    app.harmonicRatios = defaultHarmonicRatios(app.orders);
    app.harmonicRatios2 = app.harmonicRatios;
    app.params1 = struct('baseAmp', 0.75, 'harmonicScale', 0.10, 'noiseAmp', 0.005);
    app.params2 = app.params1;

    app.fig = figure( ...
        'Name', '电能质量模拟采样信号 Q1.15', ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'MenuBar', 'none', ...
        'ToolBar', 'figure', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.06 0.88 0.86]);
    set(app.fig, 'WindowScrollWheelFcn', @(~, event) onMouseWheel(event));

    app.ctrl = uipanel(app.fig, ...
        'Title', '参数配置', ...
        'FontWeight', 'bold', ...
        'Units', 'normalized', ...
        'Position', [0.015 0.02 0.30 0.96]);

    app.plotPanel = uipanel(app.fig, ...
        'Title', '数据视图', ...
        'FontWeight', 'bold', ...
        'Units', 'normalized', ...
        'Position', [0.33 0.02 0.655 0.96]);

    app.axTime = subplot(3, 1, 1, 'Parent', app.plotPanel);
    app.axFreq = subplot(3, 1, 2, 'Parent', app.plotPanel);
    app.axPhase = subplot(3, 1, 3, 'Parent', app.plotPanel);

    createControls();
    refreshHarmonicRows();
    regenerateData();

    function createControls()
        y = 0.945;
        h = 0.032;
        gap = 0.006;

        addLabel('采样点数 n', y);
        app.editN = addEdit('8192', y - h);
        y = y - 2*h - gap;

        addLabel('采样频率 fs / Hz', y);
        app.editFs = addEdit('200000', y - h);
        y = y - 2*h - gap;

        addLabel('基频 f0 / Hz', y);
        app.editF0 = addEdit('50', y - h);
        y = y - 2*h - gap;

        addLabel('基波幅值', y);
        app.editBaseAmp = addEdit('0.75', y - h);
        y = y - 2*h - gap;

        addLabel('整体谐波强度倍率', y);
        app.editHarmonicScale = addEdit('0.10', y - h);
        y = y - 2*h - gap;

        addLabel('白噪声幅值', y);
        app.editNoiseAmp = addEdit('0.005', y - h);
        y = y - 2*h - gap;

        app.checkNormalize = uicontrol(app.ctrl, ...
            'Style', 'checkbox', ...
            'String', '自动归一化防止溢出', ...
            'Value', 1, ...
            'Units', 'normalized', ...
            'Position', [0.07 y 0.86 h], ...
            'BackgroundColor', 'w');
        y = y - h - gap;

        app.checkRandomPhase = uicontrol(app.ctrl, ...
            'Style', 'checkbox', ...
            'String', '随机相位', ...
            'Value', 1, ...
            'Units', 'normalized', ...
            'Position', [0.07 y 0.86 h], ...
            'BackgroundColor', 'w');
        y = y - h - gap;

        app.randomButton = uicontrol(app.ctrl, ...
            'Style', 'pushbutton', ...
            'String', '随机谐波比例', ...
            'Units', 'normalized', ...
            'Position', [0.07 y 0.86 h], ...
            'Callback', @(~, ~) randomizeHarmonics());

        app.harmonicPanel = uipanel(app.ctrl, ...
            'Title', '2~50 次谐波比例，总和=1', ...
            'Units', 'normalized', ...
            'Position', [0.05 0.20 0.90 0.23]);

        app.rowOrderLabels = gobjects(app.visibleRows, 1);
        app.rowEdits = gobjects(app.visibleRows, 1);
        app.rowMinusButtons = gobjects(app.visibleRows, 1);
        app.rowPlusButtons = gobjects(app.visibleRows, 1);

        rowH = 0.125;
        for row = 1:app.visibleRows
            rowY = 0.89 - (row - 1) * rowH;
            app.rowOrderLabels(row) = uicontrol(app.harmonicPanel, ...
                'Style', 'text', ...
                'String', '', ...
                'Units', 'normalized', ...
                'Position', [0.04 rowY 0.18 0.075], ...
                'BackgroundColor', 'w', ...
                'HorizontalAlignment', 'left');

            app.rowEdits(row) = uicontrol(app.harmonicPanel, ...
                'Style', 'edit', ...
                'String', '', ...
                'Units', 'normalized', ...
                'Position', [0.25 rowY 0.30 0.08], ...
                'BackgroundColor', 'w', ...
                'Callback', @(src, ~) onRatioEdited(src));

            app.rowMinusButtons(row) = uicontrol(app.harmonicPanel, ...
                'Style', 'pushbutton', ...
                'String', '-', ...
                'Units', 'normalized', ...
                'Position', [0.59 rowY 0.14 0.08], ...
                'Callback', @(src, ~) stepRatio(src, -1));

            app.rowPlusButtons(row) = uicontrol(app.harmonicPanel, ...
                'Style', 'pushbutton', ...
                'String', '+', ...
                'Units', 'normalized', ...
                'Position', [0.76 rowY 0.14 0.08], ...
                'Callback', @(src, ~) stepRatio(src, 1));
        end

        app.harmonicSlider = uicontrol(app.harmonicPanel, ...
            'Style', 'slider', ...
            'Units', 'normalized', ...
            'Position', [0.91 0.07 0.07 0.88], ...
            'Min', 1, ...
            'Max', numel(app.orders) - app.visibleRows + 1, ...
            'Value', 1, ...
            'SliderStep', [1/(numel(app.orders)-app.visibleRows), app.visibleRows/(numel(app.orders)-app.visibleRows)], ...
            'Callback', @(src, ~) onScroll(src));

        app.secondSignalButton = uicontrol(app.ctrl, ...
            'Style', 'togglebutton', ...
            'String', '启用第二路信号', ...
            'Value', 0, ...
            'Units', 'normalized', ...
            'Position', [0.07 0.138 0.38 0.038], ...
            'Callback', @(src, ~) toggleSecondSignal(src));

        app.secondConfigButton = uicontrol(app.ctrl, ...
            'Style', 'pushbutton', ...
            'String', '第二路独立配置', ...
            'Units', 'normalized', ...
            'Position', [0.07 0.102 0.38 0.032], ...
            'Callback', @(~, ~) toggleSecondConfig());

        uicontrol(app.ctrl, ...
            'Style', 'text', ...
            'String', '相位差/度', ...
            'Units', 'normalized', ...
            'Position', [0.55 0.158 0.38 0.022], ...
            'BackgroundColor', 'w', ...
            'HorizontalAlignment', 'left');

        app.editPhaseDiff = uicontrol(app.ctrl, ...
            'Style', 'edit', ...
            'String', '30', ...
            'Units', 'normalized', ...
            'Position', [0.55 0.136 0.38 0.028], ...
            'BackgroundColor', 'w', ...
            'Callback', @(~, ~) regenerateData());

        app.runButton = uicontrol(app.ctrl, ...
            'Style', 'pushbutton', ...
            'String', '重新生成', ...
            'Units', 'normalized', ...
            'Position', [0.07 0.055 0.38 0.040], ...
            'FontWeight', 'bold', ...
            'Callback', @(~, ~) regenerateData());

        app.exportButton = uicontrol(app.ctrl, ...
            'Style', 'pushbutton', ...
            'String', '导出数据集', ...
            'Units', 'normalized', ...
            'Position', [0.55 0.055 0.38 0.040], ...
            'FontWeight', 'bold', ...
            'Callback', @(~, ~) exportData());

        function addLabel(txt, ypos)
            uicontrol(app.ctrl, ...
                'Style', 'text', ...
                'String', txt, ...
                'Units', 'normalized', ...
                'Position', [0.07 ypos 0.86 h], ...
                'BackgroundColor', 'w', ...
                'HorizontalAlignment', 'left');
        end

        function edit = addEdit(txt, ypos)
            edit = uicontrol(app.ctrl, ...
                'Style', 'edit', ...
                'String', txt, ...
                'Units', 'normalized', ...
                'Position', [0.07 ypos 0.86 h], ...
                'BackgroundColor', 'w');
        end
    end

    function ratios = defaultHarmonicRatios(orders)
        weights = 1 ./ double(orders).^1.2;
        ratios = weights / sum(weights);
    end

    function randomizeHarmonics()
        weights = rand(1, numel(app.orders)) ./ double(app.orders);
        if app.editingSecond
            app.harmonicRatios2 = weights / sum(weights);
        else
            app.harmonicRatios = weights / sum(weights);
        end
        refreshHarmonicRows();
        regenerateData();
    end

    function toggleSecondSignal(src)
        app.enableSecondSignal = logical(get(src, 'Value'));
        if app.enableSecondSignal
            set(src, 'String', '关闭第二路信号');
        else
            set(src, 'String', '启用第二路信号');
        end
        regenerateData();
    end

    function toggleSecondConfig()
        syncControlsToCurrentSignal();
        app.secondIndependent = true;
        app.enableSecondSignal = true;
        if ishandle(app.secondSignalButton)
            set(app.secondSignalButton, 'Value', 1, 'String', '关闭第二路信号');
        end
        app.editingSecond = ~app.editingSecond;
        loadCurrentSignalToControls();
        refreshHarmonicRows();
        updateSecondConfigButtonText();
        regenerateData();
    end

    function syncControlsToCurrentSignal()
        targetParams = struct( ...
            'baseAmp', max(0, readNumber(app.editBaseAmp, 0.75)), ...
            'harmonicScale', max(0, readNumber(app.editHarmonicScale, 0.10)), ...
            'noiseAmp', max(0, readNumber(app.editNoiseAmp, 0.005)));
        if app.editingSecond
            app.params2 = targetParams;
            app.harmonicRatios2 = normalizeRatios(getCurrentEditorRatios());
        else
            app.params1 = targetParams;
            app.harmonicRatios = normalizeRatios(getCurrentEditorRatios());
        end
    end

    function loadCurrentSignalToControls()
        if app.editingSecond
            params = app.params2;
        else
            params = app.params1;
        end
        set(app.editBaseAmp, 'String', sprintf('%.6g', params.baseAmp));
        set(app.editHarmonicScale, 'String', sprintf('%.6g', params.harmonicScale));
        set(app.editNoiseAmp, 'String', sprintf('%.6g', params.noiseAmp));
    end

    function updateSecondConfigButtonText()
        if ~ishandle(app.secondConfigButton)
            return;
        end
        if app.editingSecond
            set(app.secondConfigButton, 'String', '正在编辑第二路');
        elseif app.secondIndependent
            set(app.secondConfigButton, 'String', '正在编辑第一路');
        else
            set(app.secondConfigButton, 'String', '第二路独立配置');
        end
    end

    function ratios = getCurrentEditorRatios()
        if app.editingSecond
            ratios = app.harmonicRatios2;
        else
            ratios = app.harmonicRatios;
        end
    end

    function setCurrentEditorRatios(ratios)
        if app.editingSecond
            app.harmonicRatios2 = normalizeRatios(ratios);
        else
            app.harmonicRatios = normalizeRatios(ratios);
        end
    end

    function onScroll(src)
        app.scrollTop = round(get(src, 'Value'));
        refreshHarmonicRows();
    end

    function onMouseWheel(event)
        if ~isfield(app, 'harmonicSlider') || ~ishandle(app.harmonicSlider)
            return;
        end
        scrollHarmonicRows(event.VerticalScrollCount);
    end

    function scrollHarmonicRows(deltaRows)
        maxTop = numel(app.orders) - app.visibleRows + 1;
        app.scrollTop = min(max(1, app.scrollTop + sign(deltaRows)), maxTop);
        set(app.harmonicSlider, 'Value', app.scrollTop);
        refreshHarmonicRows();
    end

    function refreshHarmonicRows()
        setCurrentEditorRatios(getCurrentEditorRatios());
        ratios = getCurrentEditorRatios();
        maxTop = numel(app.orders) - app.visibleRows + 1;
        app.scrollTop = min(max(1, app.scrollTop), maxTop);
        if isfield(app, 'harmonicSlider') && ishandle(app.harmonicSlider)
            set(app.harmonicSlider, 'Value', app.scrollTop);
        end

        for row = 1:app.visibleRows
            idx = app.scrollTop + row - 1;
            set(app.rowOrderLabels(row), 'String', sprintf('%02d 次', app.orders(idx)));
            set(app.rowEdits(row), 'String', sprintf('%.6f', ratios(idx)));
            set(app.rowEdits(row), 'UserData', idx);
            set(app.rowMinusButtons(row), 'UserData', idx);
            set(app.rowPlusButtons(row), 'UserData', idx);
        end

    end

    function ratios = normalizeRatios(ratios)
        ratios = max(0, ratios);
        total = sum(ratios);
        if total <= 0
            ratios = ones(size(ratios)) / numel(ratios);
        else
            ratios = ratios / total;
        end
    end

    function onRatioEdited(src)
        idx = get(src, 'UserData');
        ratios = getCurrentEditorRatios();
        oldValue = ratios(idx);
        newValue = str2double(get(src, 'String'));
        if isnan(newValue) || ~isfinite(newValue)
            newValue = oldValue;
        end
        applyRatioChange(idx, newValue);
        refreshHarmonicRows();
    end

    function stepRatio(src, direction)
        idx = get(src, 'UserData');
        step = 0.005;
        ratios = getCurrentEditorRatios();
        applyRatioChange(idx, ratios(idx) + direction * step);
        refreshHarmonicRows();
    end

    function applyRatioChange(idx, newValue)
        ratios = getCurrentEditorRatios();
        oldValue = ratios(idx);
        newValue = min(max(newValue, 0), 1);
        delta = newValue - oldValue;

        if abs(delta) < eps
            ratios(idx) = newValue;
            setCurrentEditorRatios(ratios);
            return;
        end

        otherIdx = setdiff(1:numel(ratios), idx);
        otherSum = sum(ratios(otherIdx));
        ratios(idx) = newValue;

        if delta > 0
            reduceAmount = min(delta, otherSum);
            if otherSum > 0
                ratios(otherIdx) = ratios(otherIdx) - reduceAmount * ratios(otherIdx) / otherSum;
            end
            ratios(idx) = oldValue + reduceAmount;
        else
            addAmount = -delta;
            if otherSum > 0
                ratios(otherIdx) = ratios(otherIdx) + addAmount * ratios(otherIdx) / otherSum;
            else
                ratios(otherIdx) = addAmount / numel(otherIdx);
            end
        end

        setCurrentEditorRatios(ratios);
    end

    function cfg = readConfig()
        syncControlsToCurrentSignal();
        cfg.n = max(16, round(readNumber(app.editN, 8192)));
        cfg.fs = max(2 * 50 * 50, readNumber(app.editFs, 200000));
        cfg.f0 = max(0.001, readNumber(app.editF0, 50));
        cfg.baseAmp = app.params1.baseAmp;
        cfg.harmonicScale = app.params1.harmonicScale;
        cfg.noiseAmp = app.params1.noiseAmp;
        cfg.baseAmp2 = app.params1.baseAmp;
        cfg.harmonicScale2 = app.params1.harmonicScale;
        cfg.noiseAmp2 = app.params1.noiseAmp;
        if app.secondIndependent
            cfg.baseAmp2 = app.params2.baseAmp;
            cfg.harmonicScale2 = app.params2.harmonicScale;
            cfg.noiseAmp2 = app.params2.noiseAmp;
        end
        cfg.phaseDiffDeg = readNumber(app.editPhaseDiff, 30);
        cfg.phaseDiffRad = cfg.phaseDiffDeg * pi / 180;
        cfg.enableSecondSignal = app.enableSecondSignal;
        cfg.secondIndependent = app.secondIndependent;
        cfg.normalize = logical(get(app.checkNormalize, 'Value'));
        cfg.randomPhase = logical(get(app.checkRandomPhase, 'Value'));
        cfg.orders = app.orders;
        cfg.ratios = normalizeRatios(app.harmonicRatios);
        cfg.ratios2 = cfg.ratios;
        if app.secondIndependent
            cfg.ratios2 = normalizeRatios(app.harmonicRatios2);
        end
        app.harmonicRatios = cfg.ratios;
        app.harmonicRatios2 = cfg.ratios2;
    end

    function val = readNumber(handle, defaultValue)
        val = str2double(get(handle, 'String'));
        if isnan(val) || ~isfinite(val)
            val = defaultValue;
            set(handle, 'String', num2str(defaultValue));
        end
    end

    function regenerateData()
        cfg = readConfig();
        refreshHarmonicRows();

        t = (0:cfg.n-1) / cfg.fs;
        if cfg.randomPhase
            phase0 = 2*pi*rand();
            harmonicPhase = 2*pi*rand(size(cfg.orders));
        else
            phase0 = 0;
            harmonicPhase = zeros(size(cfg.orders));
        end
        phaseDiff1Deg = wrapDegrees((harmonicPhase - cfg.orders * phase0) * 180 / pi);
        phaseDiff2Deg = wrapDegrees((harmonicPhase + cfg.orders * cfg.phaseDiffRad ...
            - cfg.orders * (phase0 + cfg.phaseDiffRad)) * 180 / pi);

        x = cfg.baseAmp * sin(2*pi*cfg.f0*t + phase0);
        x2 = cfg.baseAmp2 * sin(2*pi*cfg.f0*t + phase0 + cfg.phaseDiffRad);
        harmonicTable = zeros(numel(cfg.orders), 5);
        harmonicTable2 = zeros(numel(cfg.orders), 5);

        for i = 1:numel(cfg.orders)
            order = cfg.orders(i);
            ratio = cfg.ratios(i) * cfg.harmonicScale;
            amp = cfg.baseAmp * ratio;
            ratio2 = cfg.ratios2(i) * cfg.harmonicScale2;
            amp2 = cfg.baseAmp2 * ratio2;
            phase = harmonicPhase(i);
            x = x + amp * sin(2*pi*cfg.f0*order*t + phase);
            x2 = x2 + amp2 * sin(2*pi*cfg.f0*order*t + phase + order * cfg.phaseDiffRad);
            harmonicTable(i, :) = [order, cfg.f0*order, cfg.ratios(i), ratio, amp];
            harmonicTable2(i, :) = [order, cfg.f0*order, cfg.ratios2(i), ratio2, amp2];
        end

        x = x + cfg.noiseAmp * randn(size(x));
        x2 = x2 + cfg.noiseAmp2 * randn(size(x2));

        peakBefore = max(abs(x));
        if cfg.enableSecondSignal
            peakBefore = max(peakBefore, max(abs(x2)));
        end
        if cfg.normalize && peakBefore >= 0.999
            x = 0.999 * x / peakBefore;
            x2 = 0.999 * x2 / peakBefore;
        end

        [xQ15Int, xQ15Hex, xQ15, quantError] = quantizeQ15(x);
        [x2Q15Int, x2Q15Hex, x2Q15, quantError2] = quantizeQ15(x2);
        [freq, mag] = spectrumQ15(xQ15, cfg.fs);

        app.data = struct( ...
            'cfg', cfg, ...
            't', t, ...
            'x', x, ...
            'xQ15Int', xQ15Int, ...
            'xQ15Hex', xQ15Hex, ...
            'xQ15', xQ15, ...
            'quantError', quantError, ...
            'x2', x2, ...
            'x2Q15Int', x2Q15Int, ...
            'x2Q15Hex', x2Q15Hex, ...
            'x2Q15', x2Q15, ...
            'quantError2', quantError2, ...
            'freq', freq, ...
            'mag', mag, ...
            'harmonicTable', harmonicTable, ...
            'harmonicTable2', harmonicTable2, ...
            'phaseDiff1Deg', phaseDiff1Deg, ...
            'phaseDiff2Deg', phaseDiff2Deg);

        updatePlots();
    end

    function deg = wrapDegrees(deg)
        deg = mod(deg + 180, 360) - 180;
    end

    function [xQ15Int, xQ15Hex, xQ15, quantError] = quantizeQ15(x)
        scale = 2^15;
        xQ15Int = round(x * scale);
        xQ15Int = min(max(xQ15Int, -32768), 32767);
        xQ15Uint = uint16(mod(int32(xQ15Int), 2^16));
        xQ15Hex = upper(dec2hex(xQ15Uint, 4));
        xQ15 = double(xQ15Int) / scale;
        quantError = x - xQ15;
    end

    function [freq, mag] = spectrumQ15(xQ15, fs)
        n = numel(xQ15);
        nfft = 2^nextpow2(n);
        freq = fs * (0:nfft/2) / nfft;
        X = fft(xQ15, nfft) / n;
        mag = 2 * abs(X(1:nfft/2+1));
    end

    function updatePlots()
        d = app.data;
        cfg = d.cfg;
        showTime = min(0.1, d.t(end));
        timeIdx = find(d.t <= showTime);
        if numel(timeIdx) > 6000
            timeIdx = timeIdx(1:ceil(numel(timeIdx)/6000):end);
        end
        freqMax = min(cfg.f0 * 55, cfg.fs/2);
        freqMask = d.freq <= freqMax;

        cla(app.axTime);
        plot(app.axTime, d.t(timeIdx), d.xQ15(timeIdx), 'Color', [0.95 0.72 0.10], 'LineWidth', 1.1); hold(app.axTime, 'on');
        if cfg.enableSecondSignal
            plot(app.axTime, d.t(timeIdx), d.x2Q15(timeIdx), 'Color', [0.10 0.65 0.25], 'LineWidth', 1.1);
        end
        grid(app.axTime, 'on');
        xlabel(app.axTime, '时间 / s');
        ylabel(app.axTime, '归一化幅值');
        title(app.axTime, '时域波形：Q1.15 量化信号');
        if cfg.enableSecondSignal
            legend(app.axTime, {'第一路信号', '第二路信号'}, 'Location', 'best');
        else
            legend(app.axTime, {'第一路信号'}, 'Location', 'best');
        end
        xlim(app.axTime, [0, showTime]);

        cla(app.axFreq);
        plot(app.axFreq, d.freq(freqMask), d.mag(freqMask), 'LineWidth', 1.0);
        grid(app.axFreq, 'on');
        xlabel(app.axFreq, '频率 / Hz');
        ylabel(app.axFreq, '幅值');
        title(app.axFreq, 'Q1.15 量化信号频谱');
        xlim(app.axFreq, [0, freqMax]);

        cla(app.axPhase);
        if cfg.enableSecondSignal
            bar(app.axPhase, cfg.orders, [d.phaseDiff1Deg(:), d.phaseDiff2Deg(:)], 'grouped');
            legend(app.axPhase, {'第一路', '第二路'}, 'Location', 'best');
        else
            bar(app.axPhase, cfg.orders, d.phaseDiff1Deg(:), 'FaceColor', [0.95 0.72 0.10]);
        end
        grid(app.axPhase, 'on');
        xlabel(app.axPhase, '谐波次数');
        ylabel(app.axPhase, '相位差 / 度');
        title(app.axPhase, '各次谐波相对基波的相位差');
        xlim(app.axPhase, [1, max(cfg.orders) + 1]);
        ylim(app.axPhase, [-180, 180]);
    end

    function exportData()
        if ~isfield(app, 'data')
            regenerateData();
        end

        d = app.data;
        outDir = uigetdir(app.defaultOutputDir, '选择数据集导出目录');
        if isequal(outDir, 0)
            return;
        end

        timeTag = datestr(now, 'yyyymmdd_HHMMSS');
        csvFile = fullfile(outDir, ['pq_signal_q15_data_' timeTag '.csv']);
        hexFile = fullfile(outDir, ['pq_signal_q15_hex_' timeTag '.txt']);
        cfgFile = fullfile(outDir, ['pq_signal_q15_config_' timeTag '.txt']);

        if d.cfg.enableSecondSignal
            out = table((0:d.cfg.n-1).', d.t.', ...
                d.x.', d.xQ15Int.', d.xQ15.', string(d.xQ15Hex), ...
                d.x2.', d.x2Q15Int.', d.x2Q15.', string(d.x2Q15Hex), ...
                'VariableNames', {'Index', 'Time_s', ...
                'Signal1_Float', 'Signal1_Q15_Int', 'Signal1_Q15_Value', 'Signal1_Q15_Hex', ...
                'Signal2_Float', 'Signal2_Q15_Int', 'Signal2_Q15_Value', 'Signal2_Q15_Hex'});
        else
            out = table((0:d.cfg.n-1).', d.t.', d.x.', d.xQ15Int.', d.xQ15.', string(d.xQ15Hex), ...
                'VariableNames', {'Index', 'Time_s', 'FloatSignal', 'Q15_Int', 'Q15_Value', 'Q15_Hex'});
        end
        writetable(out, csvFile);
        writelines(string(d.xQ15Hex), hexFile);
        writeConfigFile(cfgFile, d);

        fprintf('CSV 数据: %s\nHEX 数据: %s\n配置文件: %s\n', csvFile, hexFile, cfgFile);
    end

    function writeConfigFile(cfgFile, d)
        fid = fopen(cfgFile, 'w');
        if fid < 0
            warning('无法写入配置文件: %s', cfgFile);
            return;
        end

        cleaner = onCleanup(@() fclose(fid));
        cfg = d.cfg;
        fprintf(fid, 'n=%d\n', cfg.n);
        fprintf(fid, 'fs=%.12g\n', cfg.fs);
        fprintf(fid, 'f0=%.12g\n', cfg.f0);
        fprintf(fid, 'base_amp=%.12g\n', cfg.baseAmp);
        fprintf(fid, 'harmonic_scale=%.12g\n', cfg.harmonicScale);
        fprintf(fid, 'noise_amp=%.12g\n', cfg.noiseAmp);
        fprintf(fid, 'enable_second_signal=%d\n', cfg.enableSecondSignal);
        fprintf(fid, 'second_independent=%d\n', cfg.secondIndependent);
        fprintf(fid, 'base_amp2=%.12g\n', cfg.baseAmp2);
        fprintf(fid, 'harmonic_scale2=%.12g\n', cfg.harmonicScale2);
        fprintf(fid, 'noise_amp2=%.12g\n', cfg.noiseAmp2);
        fprintf(fid, 'phase_diff_deg=%.12g\n', cfg.phaseDiffDeg);
        fprintf(fid, 'normalize=%d\n', cfg.normalize);
        fprintf(fid, 'harmonic_ratio_sum=%.12g\n', sum(cfg.ratios));
        fprintf(fid, 'harmonic_ratio2_sum=%.12g\n', sum(cfg.ratios2));
        fprintf(fid, '\nOrder,Frequency_Hz,BaseRatio,ScaledRatio,Amplitude\n');
        for i = 1:size(d.harmonicTable, 1)
            fprintf(fid, '%d,%.12g,%.12g,%.12g,%.12g\n', d.harmonicTable(i, :));
        end
        fprintf(fid, '\nSecondSignal_Order,Frequency_Hz,BaseRatio,ScaledRatio,Amplitude\n');
        for i = 1:size(d.harmonicTable2, 1)
            fprintf(fid, '%d,%.12g,%.12g,%.12g,%.12g\n', d.harmonicTable2(i, :));
        end
        clear cleaner;
    end
end
