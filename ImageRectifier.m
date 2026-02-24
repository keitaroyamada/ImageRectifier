classdef ImageRectifier < matlab.apps.AppBase
    % -------------------------------------------------------------------------
    % UIコンポーネント
    % -------------------------------------------------------------------------
    properties (Access = public)
        UIFigure          matlab.ui.Figure
        LeftPanel         matlab.ui.container.Panel
        ScrollPanel       matlab.ui.container.Panel 
        UIAxes            matlab.ui.control.UIAxes
        RefUIAxes         matlab.ui.control.UIAxes
        
        ImgDropDown       matlab.ui.control.DropDown 
        
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
        LabelPosDropDown  matlab.ui.control.DropDown % ★追加: 文字位置選択
        UITable           matlab.ui.control.Table
        ClearBtn          matlab.ui.control.Button
        GraphCheckbox     matlab.ui.control.CheckBox
        PreviewCheckbox   matlab.ui.control.CheckBox
        ProcessBtn        matlab.ui.control.Button
        SaveBtn           matlab.ui.control.Button
    end
    % -------------------------------------------------------------------------
    % 内部データ
    % -------------------------------------------------------------------------
    properties (Access = private)
        OrigImgList = {}      
        TableDataList = {}    
        CurrentImgIdx = 1     
        
        OrigImg         
        RefImg          
        ProcessedImg
        TargetLine
        MarkerPlots
        GuidelinePlots     % 1cmごとの補助線のプロットハンドルを保持
        ImgObj          
        RefImgObj       
        LastPath = ''
        
        FirstFileName = '' 
        GraphFigure        
        
        LastMouseY = -1;
    end
    % -------------------------------------------------------------------------
    % コールバック・ロジック
    % -------------------------------------------------------------------------
    methods (Access = private)
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
        end
        
        function updateAxesLayout(app)
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
            topY = max(panelH, maxH + margin); 
            
            app.UIAxes.Position = [margin, topY - H_main, axesW_main, H_main];
            app.RefUIAxes.Position = [margin * 2 + halfW, topY - H_ref, axesW_ref, H_ref];
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
                app.ImgObj.ButtonDownFcn = @(src, event) app.ImageClicked(src, event);
                app.ImgObj.PickableParts = 'visible';
            else
                app.ImgObj.CData = app.OrigImg;
                app.ImgObj.XData = [1 W];
                app.ImgObj.YData = [1 H];
            end
            
            app.UIAxes.XLim = [0.5, W + 0.5];
            app.UIAxes.YLim = [0.5, H + 0.5];
            app.UIAxes.YDir = 'reverse';
            app.UIAxes.DataAspectRatio = [1 1 1];
            
            hold(app.UIAxes, 'on');
            if ~isempty(app.TargetLine) && isvalid(app.TargetLine)
                delete(app.TargetLine);
            end
            % ★変更: LineWidthを1.5から0.5にして線を細くした
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
        
        function LoadBtnPushed(app, ~, ~)
            startPath = app.LastPath;
            if isempty(startPath); startPath = pwd; end
            
            [file, path] = uigetfile({'*.jpg;*.png;*.tif;*.bmp', '画像ファイル'}, 'メイン画像を追加読込', startPath);
            if isequal(file, 0); return; end
            
            app.LastPath = path;
            newImg = imread(fullfile(path, file));
            
            numImgs = length(app.OrigImgList) + 1;
            app.OrigImgList{numImgs} = newImg;
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
            app.TableDataList = {};
            app.CurrentImgIdx = 1;
            app.OrigImg = [];
            app.FirstFileName = ''; 
            app.GraphFigure = [];   
            app.LastMouseY = -1;
            
            app.ImgDropDown.Items = {'No Image'};
            app.ImgDropDown.Visible = 'off';
            app.UITable.Data = zeros(0, 2);
            
            if ~isempty(app.ImgObj) && isvalid(app.ImgObj)
                delete(app.ImgObj);
            end
            if ~isempty(app.TargetLine) && isvalid(app.TargetLine)
                delete(app.TargetLine);
            end
            if ~isempty(app.MarkerPlots)
                delete(app.MarkerPlots(isvalid(app.MarkerPlots)));
                app.MarkerPlots = [];
            end
            if ~isempty(app.GuidelinePlots)
                delete(app.GuidelinePlots(isvalid(app.GuidelinePlots)));
                app.GuidelinePlots = [];
            end
            
            app.ProcessedImg = [];
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
            
            % ★追加: ユーザーが選択した文字位置の取得
            labelPos = app.LabelPosDropDown.Value;
            
            hold(app.UIAxes, 'on');
            for k = 1:numTargets
                c = cm_targets(k);
                
                if N >= 2
                    if c >= pts_cm(1) && c <= pts_cm(end)
                        lineColor = [0 0.8 0.8]; % Cyan (内挿)
                        lineStyle = '--';
                        labelSuffix = '(In)';
                    else
                        lineColor = [0.9 0 0.9]; % Magenta (外挿)
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
                    
                    % ★追加: 位置に応じたX座標とAlignmentの設定
                    if strcmp(labelPos, '左')
                        textX = 10;
                        align = 'left';
                    elseif strcmp(labelPos, '中央')
                        textX = W_orig / 2;
                        align = 'center';
                    else % 右
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
            max_W = 0;
            for i = 1:numImgs
                max_W = max(max_W, size(app.OrigImgList{i}, 2));
            end
            
            outImg = zeros(H_out, max_W, size(app.OrigImgList{1}, 3), 'uint8');
            
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
                end
                
                N = length(pts_cm);
                
                if N >= 2
                    S_nom = (pts_px(end) - pts_px(1)) / (pts_cm(end) - pts_cm(1));
                else
                    S_nom = H_orig / (total_cm / numImgs); 
                end
                
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
                
                [X_out, Y_out] = meshgrid(1:W_orig, y_in);
                outImg_i = zeros(H_out, W_orig, C, 'uint8');
                for c = 1:C
                    outImg_i(:,:,c) = uint8(interp2(double(img(:,:,c)), X_out, Y_out, 'linear', 0));
                end
                
                mask = any(outImg_i > 0, 3);
                for c = 1:C
                    ch_out = outImg(:, 1:W_orig, c);
                    ch_i = outImg_i(:,:,c);
                    ch_out(mask) = ch_i(mask);
                    outImg(:, 1:W_orig, c) = ch_out;
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
            defaultFileName = sprintf('%s_processed.png', baseName);
            
            [file, path] = uiputfile({'*.png;*.jpg;*.tif', '画像ファイル'}, 'ベース名をつけて保存', fullfile(startPath, defaultFileName));
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
            app.UIFigure.WindowButtonMotionFcn = @(src, event) app.MouseMoved(src, event);
            
            app.LeftPanel = uipanel(app.UIFigure, 'Position', [10, 10, 280, 860]);
            
            %% メイン画像コントロール
            app.ImgDropDown = uidropdown(app.LeftPanel, 'Position', [10, 825, 250, 22], ...
                'Items', {'No Image'}, 'Visible', 'off');
            app.ImgDropDown.ValueChangedFcn = @(src, event) app.ImgDropDownChanged(event);
            
            app.LoadBtn = uibutton(app.LeftPanel, 'push', 'Position', [10, 790, 135, 30], ...
                'Text', '1. 画像を追加読込', 'ButtonPushedFcn', @app.LoadBtnPushed);
            app.ClearStackBtn = uibutton(app.LeftPanel, 'push', 'Position', [150, 790, 110, 30], ...
                'Text', 'スタックをクリア', 'ButtonPushedFcn', @app.ClearStackBtnPushed);
                
            uilabel(app.LeftPanel, 'Position', [10, 755, 60, 22], 'Text', '明度');
            app.MainBrightSlider = uislider(app.LeftPanel, 'Position', [70, 766, 180, 3], ...
                'Limits', [-128, 128], 'Value', 0, 'ValueChangedFcn', @(~,~) app.updateMainImageDisplay());
                
            uilabel(app.LeftPanel, 'Position', [10, 725, 60, 22], 'Text', 'ｺﾝﾄﾗｽﾄ');
            app.MainContrastSlider = uislider(app.LeftPanel, 'Position', [70, 736, 180, 3], ...
                'Limits', [0.1, 3.0], 'Value', 1.0, 'ValueChangedFcn', @(~,~) app.updateMainImageDisplay());
            
            %% 参考画像コントロール
            app.LoadRefBtn = uibutton(app.LeftPanel, 'push', 'Position', [10, 680, 250, 30], ...
                'Text', '2. 参考画像を読み込む', 'ButtonPushedFcn', @app.LoadRefBtnPushed);
                
            uilabel(app.LeftPanel, 'Position', [10, 645, 60, 22], 'Text', '明度');
            app.RefBrightSlider = uislider(app.LeftPanel, 'Position', [70, 656, 180, 3], ...
                'Limits', [-128, 128], 'Value', 0, 'ValueChangedFcn', @(~,~) app.updateRefImageDisplay());
                
            uilabel(app.LeftPanel, 'Position', [10, 615, 60, 22], 'Text', 'ｺﾝﾄﾗｽﾄ');
            app.RefContrastSlider = uislider(app.LeftPanel, 'Position', [70, 626, 180, 3], ...
                'Limits', [0.1, 3.0], 'Value', 1.0, 'ValueChangedFcn', @(~,~) app.updateRefImageDisplay());
            
            %% 補正パラメータ設定
            % Y座標のレイアウトを調整してドロップダウンを追加
            uilabel(app.LeftPanel, 'Position', [10, 560, 100, 22], 'Text', 'Top (cm)');
            app.TopEdit = uieditfield(app.LeftPanel, 'numeric', 'Position', [110, 560, 150, 22], 'Value', 0);
            app.TopEdit.ValueChangedFcn = @(~,~) app.updateGuidelines(); 
            
            uilabel(app.LeftPanel, 'Position', [10, 530, 100, 22], 'Text', 'Bottom (cm)');
            app.BottomEdit = uieditfield(app.LeftPanel, 'numeric', 'Position', [110, 530, 150, 22], 'Value', 100);
            app.BottomEdit.ValueChangedFcn = @(~,~) app.updateGuidelines(); 
            
            uilabel(app.LeftPanel, 'Position', [10, 500, 100, 22], 'Text', 'Target dpcm');
            app.DpcmEdit = uieditfield(app.LeftPanel, 'numeric', 'Position', [110, 500, 150, 22], 'Value', 50);
            
            % ★追加: 補助線の文字位置を選択するドロップダウン
            uilabel(app.LeftPanel, 'Position', [10, 470, 100, 22], 'Text', '補助線文字位置');
            app.LabelPosDropDown = uidropdown(app.LeftPanel, 'Position', [110, 470, 150, 22], ...
                'Items', {'左', '中央', '右'}, 'Value', '中央');
            app.LabelPosDropDown.ValueChangedFcn = @(~,~) app.updateGuidelines();
            
            %% 補正点テーブル
            uilabel(app.LeftPanel, 'Position', [10, 440, 250, 22], 'Text', '補正点リスト (cm列を編集してください)');
            app.UITable = uitable(app.LeftPanel, 'Position', [10, 230, 250, 200], ...
                'ColumnName', {'Y座標 (px)', '長さ (cm)'}, 'ColumnEditable', [false, true], ...
                'Data', zeros(0,2), 'CellEditCallback', @app.TableEdited);
                
            app.ClearBtn = uibutton(app.LeftPanel, 'push', 'Position', [10, 190, 250, 30], ...
                'Text', 'リストをクリア', 'ButtonPushedFcn', @app.ClearBtnPushed);
                
            %% 出力設定・実行
            app.GraphCheckbox = uicheckbox(app.LeftPanel, 'Position', [15, 150, 200, 22], ...
                'Text', '補正関数をグラフで確認', 'Value', true);
            app.PreviewCheckbox = uicheckbox(app.LeftPanel, 'Position', [15, 120, 200, 22], ...
                'Text', '補正後にプレビュー表示', 'Value', true);
            
            app.ProcessBtn = uibutton(app.LeftPanel, 'push', 'Position', [10, 60, 250, 40], ...
                'Text', '3. 補正実行', 'ButtonPushedFcn', @app.ProcessBtnPushed);
            app.SaveBtn = uibutton(app.LeftPanel, 'push', 'Position', [10, 10, 250, 40], ...
                'Text', '4. 保存する', 'ButtonPushedFcn', @app.SaveBtnPushed);
            
            %% 右側パネル
            app.ScrollPanel = uipanel(app.UIFigure, 'Position', [300, 10, 1030, 860], 'Scrollable', 'on');
            
            app.UIAxes = uiaxes(app.ScrollPanel);
            app.UIAxes.XTick = []; app.UIAxes.YTick = [];
            app.UIAxes.XColor = 'none'; app.UIAxes.YColor = 'none';
            app.UIAxes.Interactions = []; 
            
            app.RefUIAxes = uiaxes(app.ScrollPanel);
            app.RefUIAxes.XTick = []; app.RefUIAxes.YTick = [];
            app.RefUIAxes.XColor = 'none'; app.RefUIAxes.YColor = 'none';
            app.RefUIAxes.Interactions = []; 
            
            app.updateAxesLayout();
        end
    end
    % -------------------------------------------------------------------------
    % 起動と終了
    % -------------------------------------------------------------------------
    methods (Access = public)
        function app = ImageRectifier()
            if ispc
                app.LastPath = fullfile(getenv('USERPROFILE'), 'Desktop');
            else
                app.LastPath = fullfile(getenv('HOME'), 'Desktop');
            end
            
            createComponents(app);
        end
        function delete(app)
            delete(app.UIFigure);
        end
    end
end