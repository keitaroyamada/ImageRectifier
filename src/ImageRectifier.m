classdef ImageRectifier < matlab.apps.AppBase 
    % -------------------------------------------------------------------------
    % UIコンポーネントとプロパティ
    % -------------------------------------------------------------------------
    properties (Access = public)
        UIFigure          matlab.ui.Figure
        LeftPanel         matlab.ui.container.Panel
        ScrollPanel       matlab.ui.container.Panel 
        UIAxes            matlab.ui.control.UIAxes
        RefUIAxes         matlab.ui.control.UIAxes
        
        ImgDropDown       matlab.ui.control.DropDown 
        ReloadImgBtn      matlab.ui.control.Button % 更新ボタン
        
        LoadBtn           matlab.ui.control.Button
        ClearStackBtn     matlab.ui.control.Button
        MainBrightSlider  matlab.ui.control.Slider
        MainContrastSlider matlab.ui.control.Slider
        
        LoadRefBtn        matlab.ui.control.Button
        RefBrightSlider   matlab.ui.control.Slider
        RefContrastSlider matlab.ui.control.Slider
        
        TopEdit           matlab.ui.control.NumericEditField
        BottomEdit        matlab.ui.control.NumericEditField
        DpcmEdit          matlab.ui.control.NumericEditField
        LabelPosDropDown  matlab.ui.control.DropDown
        
        UITable           matlab.ui.control.Table
        ClearBtn          matlab.ui.control.Button
        
        GraphCheckbox     matlab.ui.control.CheckBox
        PreviewCheckbox   matlab.ui.control.CheckBox
        ProcessBtn        matlab.ui.control.Button
        SaveBtn           matlab.ui.control.Button
    end
    properties (Access = private)
        OrigImgList = {}
        ImgPathList = {} 
        TableDataList = {}
        CurrentImgIdx = 1
        OrigImg = []
        RefImg = []
        ProcessedImg = []
        
        ImgObj
        RefImgObj
        TargetLine
        MarkerPlots = []
        GuidelinePlots = []
        
        LastMouseY = -1
        FirstFileName = ''
        GraphFigure
        LastPath = ''
    end
    % -------------------------------------------------------------------------
    % コールバック・ロジック
    % -------------------------------------------------------------------------
    methods (Access = private)
        
        function FigureSizeChanged(app, ~, ~)
            if ~isvalid(app.UIFigure) || ~isvalid(app.LeftPanel) || ~isvalid(app.ScrollPanel)
                return;
            end
            
            figPos = app.UIFigure.Position;
            figW = figPos(3);
            figH = figPos(4);
            
            leftW = 280;
            leftH = 860;
            margin = 10;
            
            leftY = figH - leftH - margin;
            app.LeftPanel.Position = [margin, leftY, leftW, leftH];
            
            scrollX = margin * 2 + leftW;
            scrollW = max(10, figW - scrollX - margin);
            scrollH = max(10, figH - margin * 2);
            app.ScrollPanel.Position = [scrollX, margin, scrollW, scrollH];
            
            app.updateAxesLayout();
        end

        function updateMainImageDisplay(app)
            if isempty(app.OrigImg) || isempty(app.ImgObj) || ~isvalid(app.ImgObj)
                return;
            end
            
            b = app.MainBrightSlider.Value;
            c = app.MainContrastSlider.Value;
            
            img_d = double(app.OrigImg);
            img_adj = (img_d - 128) * c + 128 + b;
            img_adj = max(0, min(255, img_adj));
            
            app.ImgObj.CData = uint8(img_adj);
            
            tempCData = app.ImgObj.CData;
            app.ImgObj.CData = [];
            drawnow limitrate;
            app.ImgObj.CData = tempCData;
        end
        
        function updateRefImageDisplay(app)
            if isempty(app.RefImg) || isempty(app.RefImgObj) || ~isvalid(app.RefImgObj)
                return;
            end
            
            b = app.RefBrightSlider.Value;
            c = app.RefContrastSlider.Value;
            
            img_d = double(app.RefImg);
            img_adj = (img_d - 128) * c + 128 + b;
            img_adj = max(0, min(255, img_adj));
            
            app.RefImgObj.CData = uint8(img_adj);
            
            tempCDataRef = app.RefImgObj.CData;
            app.RefImgObj.CData = [];
            drawnow limitrate;
            app.RefImgObj.CData = tempCDataRef;
        end
        
        function updateAxesLayout(app)
            if ~isvalid(app.ScrollPanel) || ~isvalid(app.UIAxes)
                return;
            end
            
            panelW = app.ScrollPanel.Position(3);
            panelH = app.ScrollPanel.Position(4);
            
            margin = 10;
            scrollBarW = 30;
            usableW = panelW - scrollBarW - margin * 3;
            halfW = usableW / 2;
            
            axesW_main = halfW;
            axesW_ref  = halfW; 
            
            H_main = panelH - margin * 2; 
            H_ref  = panelH - margin * 2;
            
            if ~isempty(app.OrigImg)
                [h_m, w_m, ~] = size(app.OrigImg);
                H_main = axesW_main * (h_m / w_m);
            end
            
            if ~isempty(app.RefImg)
                [h_r, w_r, ~] = size(app.RefImg);
                if ~isempty(app.OrigImg)
                    H_ref = H_main;
                    axesW_ref = H_ref * (w_r / h_r);
                else
                    H_ref = axesW_ref * (h_r / w_r);
                end
            end
            
            maxH = max([H_main, H_ref]);
            topY = max([panelH, maxH + margin]); 
            
            app.UIAxes.Position = [margin, topY - H_main, axesW_main, H_main];
            app.RefUIAxes.Position = [margin * 2 + halfW, topY - H_ref, axesW_ref, H_ref];
            
            if ~isempty(app.OrigImg) && isvalid(app.UIAxes)
                [H, W, ~] = size(app.OrigImg);
                app.UIAxes.XLim = [0.5, W + 0.5];
                app.UIAxes.YLim = [0.5, H + 0.5];
            end
            if ~isempty(app.RefImg) && isvalid(app.RefUIAxes)
                [H_r, W_r, ~] = size(app.RefImg);
                app.RefUIAxes.XLim = [0.5, W_r + 0.5];
                app.RefUIAxes.YLim = [0.5, H_r + 0.5];
            end
            
            if ~isempty(app.ImgObj) && isvalid(app.ImgObj)
                tempCData = app.ImgObj.CData;
                app.ImgObj.CData = [];
                drawnow limitrate;
                app.ImgObj.CData = tempCData;
            end
            
            if ~isempty(app.RefImgObj) && isvalid(app.RefImgObj)
                tempCDataRef = app.RefImgObj.CData;
                app.RefImgObj.CData = [];
                drawnow limitrate;
                app.RefImgObj.CData = tempCDataRef;
            end
            
            drawnow limitrate;
        end
        
        function switchImage(app, idx)
            if ~isempty(app.OrigImg) && app.CurrentImgIdx <= length(app.TableDataList)
                app.TableDataList{app.CurrentImgIdx} = app.UITable.Data;
            end
            
            app.CurrentImgIdx = idx;
            app.OrigImg = app.OrigImgList{idx};
            [H, W, ~] = size(app.OrigImg);
            
            app.updateAxesLayout();
            
            if isempty(app.ImgObj) || ~isvalid(app.ImgObj)
                app.ImgObj = image(app.UIAxes, 'CData', app.OrigImg, 'XData', [1 W], 'YData', [1 H]);
                app.ImgObj.Interpolation = 'bilinear';
                app.ImgObj.ButtonDownFcn = @(src, event) app.ImageClicked(src, event);
                app.ImgObj.PickableParts = 'visible';
            else
                app.ImgObj.CData = app.OrigImg;
                app.ImgObj.XData = [1 W];
                app.ImgObj.YData = [1 H];
                app.ImgObj.Interpolation = 'bilinear';
            end
            
            app.UIAxes.XLim = [0.5, W + 0.5];
            app.UIAxes.YLim = [0.5, H + 0.5];
            app.UIAxes.YDir = 'reverse';
            app.UIAxes.DataAspectRatio = [1 1 1];
            
            hold(app.UIAxes, 'on');
            if ~isempty(app.TargetLine) && isvalid(app.TargetLine)
                delete(app.TargetLine);
            end
            app.TargetLine = plot(app.UIAxes, [1, W], [1, 1], 'g-', 'LineWidth', 0.5, 'Visible', 'off');
            app.TargetLine.PickableParts = 'none';
            app.TargetLine.HitTest = 'off';
            hold(app.UIAxes, 'off');
            
            app.MainBrightSlider.Value = 0;
            app.MainContrastSlider.Value = 1.0;
            app.updateMainImageDisplay();
            
            app.UITable.Data = app.TableDataList{idx};
            app.updateMarkers();
            
            drawnow;
        end
        
        function ImgDropDownChanged(app, event)
            if strcmp(event.Value, 'No Image'); return; end
            idx = find(strcmp(app.ImgDropDown.Items, event.Value));
            if ~isempty(idx)
                app.switchImage(idx);
            end
        end

        function ReloadImgBtnPushed(app, ~, ~)
            if isempty(app.OrigImgList) || app.CurrentImgIdx > length(app.ImgPathList)
                return;
            end
            
            currentPath = app.ImgPathList{app.CurrentImgIdx};
            
            if isfile(currentPath)
                try
                    reloadedImg = imread(currentPath);
                    app.OrigImgList{app.CurrentImgIdx} = reloadedImg;
                    app.OrigImg = reloadedImg;
                    [H, W, ~] = size(app.OrigImg);
                    
                    if ~isempty(app.ImgObj) && isvalid(app.ImgObj)
                        app.ImgObj.CData = app.OrigImg;
                        app.ImgObj.XData = [1 W];
                        app.ImgObj.YData = [1 H];
                    end
                    
                    app.updateAxesLayout();
                    app.updateMainImageDisplay();
                    app.updateGuidelines();
                    drawnow;
                catch ME
                    uialert(app.UIFigure, ['画像の再読み込みに失敗しました: ', ME.message], 'エラー');
                end
            else
                uialert(app.UIFigure, '元の画像ファイルが見つかりません。移動または削除された可能性があります。', 'エラー');
            end
        end
        
        function LoadBtnPushed(app, ~, ~)
            startPath = app.LastPath;
            if isempty(startPath); startPath = pwd; end
            
            [file, path] = uigetfile({'*.jpg;*.png;*.tif;*.bmp', '画像ファイル'}, 'メイン画像を追加読込', startPath);
            if isequal(file, 0); return; end
            
            app.LastPath = path;
            fullFilePath = fullfile(path, file);
            newImg = imread(fullFilePath);
            
            numImgs = length(app.OrigImgList) + 1;
            app.OrigImgList{numImgs} = newImg;
            app.ImgPathList{numImgs} = fullFilePath; 
            app.TableDataList{numImgs} = zeros(0, 2);
            
            if numImgs == 1
                app.FirstFileName = file;
            end
            
            items = app.ImgDropDown.Items;
            newLabel = sprintf('Img %d: %s', numImgs, file);
            if numImgs == 1
                items = {newLabel}; 
            else
                items{numImgs} = newLabel;
            end
            app.ImgDropDown.Items = items;
            app.ImgDropDown.Visible = 'on';
            
            app.ProcessedImg = [];
            
            app.switchImage(numImgs);
            app.ImgDropDown.Value = newLabel;
            
            scroll(app.ScrollPanel, 'top');
        end
        
        function ClearStackBtnPushed(app, ~, ~)
            app.OrigImgList = {};
            app.ImgPathList = {};
            app.TableDataList = {};
            app.CurrentImgIdx = 1;
            app.OrigImg = [];
            app.RefImg = [];
            app.FirstFileName = ''; 
            app.LastMouseY = -1;
            app.ProcessedImg = [];
            
            if ~isempty(app.GraphFigure) && isvalid(app.GraphFigure)
                close(app.GraphFigure);
            end
            app.GraphFigure = [];   
            
            app.ImgDropDown.Items = {'No Image'};
            app.ImgDropDown.Visible = 'off';
            app.UITable.Data = zeros(0, 2);
            
            app.MainBrightSlider.Value = 0;
            app.MainContrastSlider.Value = 1.0;
            app.RefBrightSlider.Value = 0;
            app.RefContrastSlider.Value = 1.0;
            app.TopEdit.Value = 0;
            app.BottomEdit.Value = 100;
            app.DpcmEdit.Value = 150;
            app.LabelPosDropDown.Value = '中央';
            
            if ~isempty(app.ImgObj) && isvalid(app.ImgObj)
                delete(app.ImgObj);
            end
            app.ImgObj = [];
            
            if ~isempty(app.RefImgObj) && isvalid(app.RefImgObj)
                delete(app.RefImgObj);
            end
            app.RefImgObj = [];
            
            if ~isempty(app.TargetLine) && isvalid(app.TargetLine)
                delete(app.TargetLine);
            end
            app.TargetLine = [];
            
            if ~isempty(app.MarkerPlots)
                delete(app.MarkerPlots(isvalid(app.MarkerPlots)));
            end
            app.MarkerPlots = [];
            
            if ~isempty(app.GuidelinePlots)
                delete(app.GuidelinePlots(isvalid(app.GuidelinePlots)));
            end
            app.GuidelinePlots = [];
            
            cla(app.UIAxes);
            cla(app.RefUIAxes);
            app.updateAxesLayout();
            
            drawnow;
        end
        
        function LoadRefBtnPushed(app, ~, ~)
            startPath = app.LastPath;
            if isempty(startPath); startPath = pwd; end
            
            [file, path] = uigetfile({'*.jpg;*.png;*.tif;*.bmp', '画像ファイル'}, '参考画像を開く', startPath);
            if isequal(file, 0); return; end
            
            app.LastPath = path;
            app.RefImg = imread(fullfile(path, file));
            [H, W, ~] = size(app.RefImg);
            
            app.updateAxesLayout();
            
            app.RefImgObj = image(app.RefUIAxes, 'CData', app.RefImg, 'XData', [1 W], 'YData', [1 H]);
            app.RefImgObj.Interpolation = 'bilinear';
            app.RefImgObj.PickableParts = 'none';
            app.RefUIAxes.XLim = [0.5, W + 0.5];
            app.RefUIAxes.YLim = [0.5, H + 0.5];
            app.RefUIAxes.YDir = 'reverse';
            app.RefUIAxes.DataAspectRatio = [1 1 1];
            
            app.RefBrightSlider.Value = 0;
            app.RefContrastSlider.Value = 1.0;
            app.updateRefImageDisplay();
            
            drawnow; scroll(app.ScrollPanel, 'top');
        end
        
        function MouseMoved(app, ~, ~)
            if isempty(app.OrigImg) || isempty(app.TargetLine) || ~isvalid(app.TargetLine)
                return;
            end
            
            cp = app.UIAxes.CurrentPoint;
            x = cp(1, 1);
            y = cp(1, 2);
            [H, W, ~] = size(app.OrigImg);
            
            if x >= 1 && x <= W && y >= 1 && y <= H
                if abs(y - app.LastMouseY) >= 1.0
                    app.TargetLine.YData = [y, y];
                    if strcmp(app.TargetLine.Visible, 'off')
                        app.TargetLine.Visible = 'on';
                    end
                    app.LastMouseY = y;
                end
            else
                if strcmp(app.TargetLine.Visible, 'on')
                    app.TargetLine.Visible = 'off';
                    app.LastMouseY = -1;
                end
            end
        end
        
        function ImageClicked(app, ~, ~)
            if isempty(app.OrigImg); return; end
            
            cp = app.UIAxes.CurrentPoint;
            y_px = round(cp(1, 2)); 
            [H, ~, ~] = size(app.OrigImg);
            
            if y_px >= 1 && y_px <= H
                currData = app.UITable.Data;
                currData = [currData; y_px, 0];
                app.UITable.Data = currData;
                app.updateMarkers();
            end
        end
        
        function TableEdited(app, ~, ~)
            app.updateMarkers();
        end
        
        function updateMarkers(app)
            if ~isempty(app.MarkerPlots)
                delete(app.MarkerPlots(isvalid(app.MarkerPlots)));
                app.MarkerPlots = [];
            end
            
            data = app.UITable.Data;
            if isempty(data) || isempty(app.OrigImg)
                app.updateGuidelines(); 
                return; 
            end
            
            W = size(app.OrigImg, 2);
            numRows = size(data, 1);
            
            tempPlots = gobjects(1, numRows * 2);
            plotIdx = 1;
            
            hold(app.UIAxes, 'on');
            for i = 1:numRows
                y = data(i, 1);
                p1 = plot(app.UIAxes, [1, W], [y, y], 'r-', 'LineWidth', 1.2);
                p1.PickableParts = 'none';
                p1.HitTest = 'off'; 
                
                p2 = text(app.UIAxes, 20, y - 15, num2str(i), ...
                    'Color', 'red', 'FontSize', 12, 'FontWeight', 'bold', ...
                    'BackgroundColor', 'white', 'Margin', 1);
                p2.PickableParts = 'none';
                p2.HitTest = 'off'; 
                
                tempPlots(plotIdx) = p1;
                tempPlots(plotIdx+1) = p2;
                plotIdx = plotIdx + 2;
            end
            hold(app.UIAxes, 'off');
            
            app.MarkerPlots = tempPlots(isvalid(tempPlots));
            app.updateGuidelines();
        end
        
        function updateGuidelines(app)
            if ~isempty(app.GuidelinePlots)
                delete(app.GuidelinePlots(isvalid(app.GuidelinePlots)));
                app.GuidelinePlots = [];
            end
            
            if isempty(app.OrigImg) || isempty(app.OrigImgList)
                return;
            end
            
            i = app.CurrentImgIdx;
            data = app.UITable.Data;
            
            if isempty(data)
                pts_px = []; pts_cm = [];
            else
                pts_px = data(:, 1);
                pts_cm = data(:, 2);
                [pts_cm, sortIdx] = sort(pts_cm);
                pts_px = pts_px(sortIdx);
                
                % ★修正: 重複するcm値を取り除く（安定ソートにより最初のpx値を採用）
                [pts_cm, uniqueIdx] = unique(pts_cm, 'stable');
                pts_px = pts_px(uniqueIdx);
            end
            
            top_cm = app.TopEdit.Value;
            bottom_cm = app.BottomEdit.Value;
            total_cm = bottom_cm - top_cm;
            if total_cm <= 0
                return;
            end
            
            numImgs = length(app.OrigImgList);
            [H_orig, W_orig, ~] = size(app.OrigImg);
            N = length(pts_cm);
            
            if N >= 2
                S_nom = (pts_px(end) - pts_px(1)) / (pts_cm(end) - pts_cm(1));
            else
                S_nom = H_orig / (total_cm / numImgs); 
            end
            
            cm_targets = ceil(top_cm) : floor(bottom_cm);
            numTargets = length(cm_targets);
            
            tempPlots = gobjects(1, numTargets * 2);
            plotIdx = 1;
            
            labelPos = app.LabelPosDropDown.Value;
            
            hold(app.UIAxes, 'on');
            for k = 1:numTargets
                c = cm_targets(k);
                
                if N >= 2
                    if c >= pts_cm(1) && c <= pts_cm(end)
                        lineColor = [0 0.8 0.8]; % Cyan
                        lineStyle = '--';
                        labelSuffix = '(In)';
                    else
                        lineColor = [0.9 0 0.9]; % Magenta
                        lineStyle = ':';
                        labelSuffix = '(Ex)';
                    end
                elseif N == 1
                    if c == pts_cm(1)
                        lineColor = [0 0.8 0.8];
                        lineStyle = '--';
                        labelSuffix = '(In)';
                    else
                        lineColor = [0.9 0 0.9];
                        lineStyle = ':';
                        labelSuffix = '(Ex)';
                    end
                else
                    lineColor = [0.9 0.5 0]; % Orange
                    lineStyle = ':';
                    labelSuffix = '(Auto)';
                end
                
                if N == 0
                    offset_cm = top_cm + (i-1)*(total_cm / numImgs);
                    y = (c - offset_cm) * S_nom + 1;
                elseif N == 1
                    y = pts_px(1) + (c - pts_cm(1)) * S_nom;
                else
                    if c < pts_cm(1)
                        y = pts_px(1) + (c - pts_cm(1)) * S_nom;
                    elseif c > pts_cm(end)
                        y = pts_px(end) + (c - pts_cm(end)) * S_nom;
                    else
                        y = interp1(pts_cm, pts_px, c, 'linear');
                    end
                end
                
                if y >= 1 && y <= H_orig
                    p1 = plot(app.UIAxes, [1, W_orig], [y, y], 'Color', lineColor, 'LineStyle', lineStyle, 'LineWidth', 1.2);
                    p1.PickableParts = 'none';
                    p1.HitTest = 'off';
                    
                    labelStr = sprintf('%d cm %s', c, labelSuffix);
                    
                    if strcmp(labelPos, '左')
                        textX = 10;
                        align = 'left';
                    elseif strcmp(labelPos, '中央')
                        textX = W_orig / 2;
                        align = 'center';
                    else
                        textX = W_orig - 10;
                        align = 'right';
                    end
                    
                    p2 = text(app.UIAxes, textX, y - 10, labelStr, ...
                        'Color', lineColor * 0.8, 'FontSize', 10, 'FontWeight', 'bold', ...
                        'HorizontalAlignment', align, 'BackgroundColor', [1 1 1 0.7], 'Margin', 1);
                    p2.PickableParts = 'none';
                    p2.HitTest = 'off'; 
                    
                    tempPlots(plotIdx) = p1;
                    tempPlots(plotIdx+1) = p2;
                    plotIdx = plotIdx + 2;
                end
            end
            hold(app.UIAxes, 'off');
            
            app.GuidelinePlots = tempPlots(isvalid(tempPlots));
        end
        
        function ClearBtnPushed(app, ~, ~)
            app.UITable.Data = zeros(0, 2);
            app.updateMarkers();
        end
        
        function ProcessBtnPushed(app, ~, ~)
            if isempty(app.OrigImgList)
                uialert(app.UIFigure, '画像を読み込んでください。', 'エラー');
                return;
            end
            
            app.TableDataList{app.CurrentImgIdx} = app.UITable.Data;
            
            top_cm = app.TopEdit.Value;
            bottom_cm = app.BottomEdit.Value;
            dpcm = app.DpcmEdit.Value;
            total_cm = bottom_cm - top_cm;
            
            if total_cm <= 0
                uialert(app.UIFigure, 'Bottom(cm)はTop(cm)より大きくしてください。', 'エラー');
                return;
            end
            
            H_out = round(total_cm * dpcm);
            cm_out = top_cm + ((0 : H_out - 1) / dpcm);
            
            numImgs = length(app.OrigImgList);
            
            W_out_max = 0;
            S_nom_list = zeros(numImgs, 1);
            
            for i = 1:numImgs
                [H_orig, W_orig, ~] = size(app.OrigImgList{i});
                data = app.TableDataList{i};
                
                if isempty(data)
                    pts_px = []; pts_cm = [];
                else
                    pts_px = data(:, 1);
                    pts_cm = data(:, 2);
                    [pts_cm, sortIdx] = sort(pts_cm);
                    pts_px = pts_px(sortIdx);
                    
                    % ★修正: 重複を排除
                    [pts_cm, uniqueIdx] = unique(pts_cm, 'stable');
                    pts_px = pts_px(uniqueIdx);
                end
                
                N = length(pts_cm);
                if N >= 2
                    S_nom = (pts_px(end) - pts_px(1)) / (pts_cm(end) - pts_cm(1));
                else
                    S_nom = H_orig / (total_cm / numImgs); 
                end
                S_nom_list(i) = S_nom;
                
                w_out_i = round(W_orig * (dpcm / S_nom));
                W_out_max = max(W_out_max, w_out_i);
            end
            
            outImg = zeros(H_out, W_out_max, size(app.OrigImgList{1}, 3), 'uint8');
            
            figure_plotted = false;
            if app.GraphCheckbox.Value
                if ~isempty(app.GraphFigure) && isvalid(app.GraphFigure)
                    close(app.GraphFigure);
                end
                app.GraphFigure = figure('Name', '補正関数マッピング (スタック)', 'NumberTitle', 'off');
                hold on; grid on; set(gca, 'YDir', 'reverse');
                xlabel('出力先の物理座標 (cm)');
                ylabel('元画像の累積ピクセル座標 (Y px)'); 
                title('各スタック画像の座標変換マッピング関数');
                colors = lines(numImgs);
                figure_plotted = true;
            end
            
            y_offset = 0; 
            
            for i = 1:numImgs
                img = app.OrigImgList{i};
                [H_orig, W_orig, C] = size(img);
                data = app.TableDataList{i};
                
                if isempty(data)
                    pts_px = []; pts_cm = [];
                else
                    pts_px = data(:, 1);
                    pts_cm = data(:, 2);
                    [pts_cm, sortIdx] = sort(pts_cm);
                    pts_px = pts_px(sortIdx);
                    
                    % ★修正: 重複を排除
                    [pts_cm, uniqueIdx] = unique(pts_cm, 'stable');
                    pts_px = pts_px(uniqueIdx);
                end
                
                N = length(pts_cm);
                S_nom = S_nom_list(i);
                
                if N == 0
                    offset_cm = top_cm + (i-1)*(total_cm / numImgs);
                    y_in = (cm_out - offset_cm) * S_nom + 1;
                elseif N == 1
                    y_in = pts_px(1) + (cm_out - pts_cm(1)) * S_nom;
                else
                    y_in = interp1(pts_cm, pts_px, cm_out, 'linear');
                    idx_left = cm_out < pts_cm(1);
                    idx_right = cm_out > pts_cm(end);
                    y_in(idx_left) = pts_px(1) + (cm_out(idx_left) - pts_cm(1)) * S_nom;
                    y_in(idx_right) = pts_px(end) + (cm_out(idx_right) - pts_cm(end)) * S_nom;
                end
                
                if figure_plotted
                    y_plot = y_in + y_offset;
                    pts_px_plot = pts_px + y_offset;
                    
                    valid_mask = (y_in >= 1) & (y_in <= H_orig);
                    cm_valid = cm_out(valid_mask);
                    y_plot_valid = y_plot(valid_mask);
                    
                    if N >= 2
                        plot(cm_valid, y_plot_valid, '--', 'Color', colors(i,:), 'LineWidth', 1.5, 'HandleVisibility', 'off');
                        idx_interp = (cm_valid >= pts_cm(1)) & (cm_valid <= pts_cm(end));
                        plot(cm_valid(idx_interp), y_plot_valid(idx_interp), '-', 'Color', colors(i,:), 'LineWidth', 1.5, 'DisplayName', sprintf('画像 %d', i));
                    else
                        plot(cm_valid, y_plot_valid, '--', 'Color', colors(i,:), 'LineWidth', 1.5, 'DisplayName', sprintf('画像 %d (外挿のみ)', i));
                    end
                    
                    if ~isempty(pts_cm)
                        plot(pts_cm, pts_px_plot, 'o', 'Color', colors(i,:), 'MarkerFaceColor', colors(i,:), 'HandleVisibility', 'off');
                    end
                end
                
                W_out_i = round(W_orig * (dpcm / S_nom));
                x_in = ((1:W_out_i) - 1) * (S_nom / dpcm) + 1;
                
                [X_out_grid, Y_out_grid] = meshgrid(x_in, y_in);
                
                outImg_i = zeros(H_out, W_out_i, C, 'uint8');
                for c = 1:C
                    outImg_i(:,:,c) = uint8(interp2(double(img(:,:,c)), X_out_grid, Y_out_grid, 'linear', 0));
                end
                
                mask = any(outImg_i > 0, 3);
                for c = 1:C
                    ch_out = outImg(:, 1:W_out_i, c);
                    ch_i = outImg_i(:,:,c);
                    ch_out(mask) = ch_i(mask);
                    outImg(:, 1:W_out_i, c) = ch_out;
                end
                
                y_offset = y_offset + H_orig;
            end
            
            if figure_plotted
                legend('show', 'Location', 'best');
            end
            
            app.ProcessedImg = outImg;
            
            if app.PreviewCheckbox.Value
                figure('Name', '補正プレビュー', 'NumberTitle', 'off');
                imshow(outImg);
            end
        end
        
        function SaveBtnPushed(app, ~, ~)
            if isempty(app.ProcessedImg)
                uialert(app.UIFigure, '先に補正を実行してください。', 'エラー');
                return;
            end
            
            startPath = app.LastPath;
            if isempty(startPath); startPath = pwd; end
            
            baseName = 'output';
            if ~isempty(app.FirstFileName)
                [~, bName, ~] = fileparts(app.FirstFileName);
                baseName = bName;
            end
            
            defaultFileName = sprintf('%s_processed.jpg', baseName);
            [file, path] = uiputfile({ ...
                '*.jpg;*.jpeg', 'JPEG 画像 (*.jpg, *.jpeg)'; ...
                '*.png', 'PNG 画像 (*.png)'; ...
                '*.tif;*.tiff', 'TIFF 画像 (*.tif, *.tiff)'}, ...
                'ベース名をつけて保存', fullfile(startPath, defaultFileName));
                
            if isequal(file, 0); return; end
            
            app.LastPath = path;
            [~, chosenBaseName, ~] = fileparts(file);
            
            imwrite(app.ProcessedImg, fullfile(path, file));
            
            allData = [];
            for i = 1:length(app.TableDataList)
                data = app.TableDataList{i};
                if ~isempty(data)
                    imgIdxCol = repmat(i, size(data, 1), 1);
                    allData = [allData; imgIdxCol, data(:, 1), data(:, 2)];
                end
            end
            if ~isempty(allData)
                T = array2table(allData, 'VariableNames', {'ImageIndex', 'Y_px', 'Length_cm'});
                csvFileName = fullfile(path, sprintf('%s_list.csv', chosenBaseName));
                writetable(T, csvFileName);
            end
            
            if app.GraphCheckbox.Value && ~isempty(app.GraphFigure) && isvalid(app.GraphFigure)
                plotFileName = fullfile(path, sprintf('%s_plot.png', chosenBaseName));
                exportgraphics(app.GraphFigure, plotFileName, 'Resolution', 300);
            end
            
            uialert(app.UIFigure, '画像、補正リストCSV、プロットの保存が完了しました。', '保存成功');
        end
    end
    
    % -------------------------------------------------------------------------
    % アプリのレイアウト構築
    % -------------------------------------------------------------------------
    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Position', [100, 100, 1350, 880], 'Name', 'Vertical Image Warper (Stack & Dual View)');
            app.UIFigure.AutoResizeChildren = 'off';
            app.UIFigure.WindowButtonMotionFcn = @(src, event) app.MouseMoved(src, event);
            app.UIFigure.SizeChangedFcn = @(src, event) app.FigureSizeChanged(src, event); 
            
            app.LeftPanel = uipanel(app.UIFigure, 'Position', [10, 10, 280, 860], 'AutoResizeChildren', 'off');
            
            app.ImgDropDown = uidropdown(app.LeftPanel, 'Position', [10, 825, 215, 22], ...
                'Items', {'No Image'}, 'Visible', 'off');
            app.ImgDropDown.ValueChangedFcn = @(src, event) app.ImgDropDownChanged(event);
            
            app.ReloadImgBtn = uibutton(app.LeftPanel, 'push', 'Position', [230, 825, 40, 22], ...
                'Text', '更新', 'ButtonPushedFcn', @app.ReloadImgBtnPushed);
            
            app.LoadBtn = uibutton(app.LeftPanel, 'push', 'Position', [10, 790, 135, 30], ...
                'Text', '1. 画像を追加読込', 'ButtonPushedFcn', @app.LoadBtnPushed);
            app.ClearStackBtn = uibutton(app.LeftPanel, 'push', 'Position', [150, 790, 110, 30], ...
                'Text', 'スタックをクリア', 'ButtonPushedFcn', @app.ClearStackBtnPushed);
                
            uilabel(app.LeftPanel, 'Position', [10, 755, 60, 22], 'Text', '明度');
            app.MainBrightSlider = uislider(app.LeftPanel, 'Position', [70, 765, 190, 3], 'Limits', [-128 128], 'Value', 0);
            app.MainBrightSlider.ValueChangedFcn = @(src, event) app.updateMainImageDisplay();
            
            uilabel(app.LeftPanel, 'Position', [10, 720, 80, 22], 'Text', 'コントラスト');
            app.MainContrastSlider = uislider(app.LeftPanel, 'Position', [90, 730, 170, 3], 'Limits', [0 3], 'Value', 1);
            app.MainContrastSlider.ValueChangedFcn = @(src, event) app.updateMainImageDisplay();
            
            app.LoadRefBtn = uibutton(app.LeftPanel, 'push', 'Position', [10, 670, 250, 30], ...
                'Text', '2. 参照画像を開く', 'ButtonPushedFcn', @app.LoadRefBtnPushed);
                
            uilabel(app.LeftPanel, 'Position', [10, 635, 60, 22], 'Text', '明度');
            app.RefBrightSlider = uislider(app.LeftPanel, 'Position', [70, 645, 190, 3], 'Limits', [-128 128], 'Value', 0);
            app.RefBrightSlider.ValueChangedFcn = @(src, event) app.updateRefImageDisplay();
            
            uilabel(app.LeftPanel, 'Position', [10, 600, 80, 22], 'Text', 'コントラスト');
            app.RefContrastSlider = uislider(app.LeftPanel, 'Position', [90, 610, 170, 3], 'Limits', [0 3], 'Value', 1);
            app.RefContrastSlider.ValueChangedFcn = @(src, event) app.updateRefImageDisplay();
            
            uilabel(app.LeftPanel, 'Position', [10, 550, 60, 22], 'Text', 'Top (cm)');
            app.TopEdit = uieditfield(app.LeftPanel, 'numeric', 'Position', [70, 550, 60, 22], 'Value', 0);
            app.TopEdit.ValueChangedFcn = @(src, event) app.updateGuidelines(); % ★追加
            
            uilabel(app.LeftPanel, 'Position', [140, 550, 50, 22], 'Text', 'Bottom');
            app.BottomEdit = uieditfield(app.LeftPanel, 'numeric', 'Position', [190, 550, 70, 22], 'Value', 100);
            app.BottomEdit.ValueChangedFcn = @(src, event) app.updateGuidelines(); % ★追加
            
            uilabel(app.LeftPanel, 'Position', [10, 520, 40, 22], 'Text', 'dpcm');
            app.DpcmEdit = uieditfield(app.LeftPanel, 'numeric', 'Position', [50, 520, 60, 22], 'Value', 150);
            app.DpcmEdit.ValueChangedFcn = @(src, event) app.updateGuidelines(); % ★追加
            
            uilabel(app.LeftPanel, 'Position', [120, 520, 70, 22], 'Text', 'ラベル位置');
            app.LabelPosDropDown = uidropdown(app.LeftPanel, 'Position', [190, 520, 70, 22], ...
                'Items', {'左', '中央', '右'}, 'Value', '中央');
            app.LabelPosDropDown.ValueChangedFcn = @(src, event) app.updateGuidelines();
            
            uilabel(app.LeftPanel, 'Position', [10, 480, 250, 22], 'Text', '3. マーカー設定 (画像クリックで追加)');
            app.UITable = uitable(app.LeftPanel, 'Position', [10, 320, 250, 150], ...
                'ColumnName', {'Y px', 'Length cm'}, 'ColumnEditable', [true, true], 'Data', zeros(0,2));
            app.UITable.CellEditCallback = @(src, event) app.TableEdited(src, event);
            
            app.ClearBtn = uibutton(app.LeftPanel, 'push', 'Position', [10, 280, 250, 30], ...
                'Text', 'テーブルをクリア', 'ButtonPushedFcn', @app.ClearBtnPushed);
                
            app.GraphCheckbox = uicheckbox(app.LeftPanel, 'Position', [10, 230, 250, 22], 'Text', 'グラフを描画する', 'Value', true);
            app.PreviewCheckbox = uicheckbox(app.LeftPanel, 'Position', [10, 200, 250, 22], 'Text', 'プレビューを表示する', 'Value', true);
            
            app.ProcessBtn = uibutton(app.LeftPanel, 'push', 'Position', [10, 150, 250, 40], ...
                'Text', '4. 補正処理を実行', 'ButtonPushedFcn', @app.ProcessBtnPushed);
                
            app.SaveBtn = uibutton(app.LeftPanel, 'push', 'Position', [10, 90, 250, 40], ...
                'Text', '5. 結果を保存', 'ButtonPushedFcn', @app.SaveBtnPushed);
                
            app.ScrollPanel = uipanel(app.UIFigure, 'Position', [300, 10, 1040, 860], 'Scrollable', 'on', 'AutoResizeChildren', 'off');
            app.UIAxes = uiaxes(app.ScrollPanel, 'Position', [10, 10, 500, 800], 'YDir', 'reverse', 'XTick', [], 'YTick', []);
            app.UIAxes.Toolbar.Visible = 'off';
            app.UIAxes.Interactions = [];
            
            app.RefUIAxes = uiaxes(app.ScrollPanel, 'Position', [520, 10, 500, 800], 'YDir', 'reverse', 'XTick', [], 'YTick', []);
            app.RefUIAxes.Toolbar.Visible = 'off';
            app.RefUIAxes.Interactions = [];
            
            app.FigureSizeChanged();
        end
    end
    
    % -------------------------------------------------------------------------
    % アプリ初期化と終了
    % -------------------------------------------------------------------------
    methods (Access = public)
        function app = ImageRectifier
            createComponents(app);
            registerApp(app, app.UIFigure);
            if nargout == 0
                clear app
            end
        end
        
        function delete(app)
            delete(app.UIFigure)
            if ~isempty(app.GraphFigure) && isvalid(app.GraphFigure)
                close(app.GraphFigure);
            end
        end
    end
end