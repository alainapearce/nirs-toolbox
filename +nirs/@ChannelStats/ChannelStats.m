classdef ChannelStats
    %CHANNELSTATS Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        description
        names           % variable names
        beta            % nconds x nchannels
        covb            % nconds x nconds x nchannels
        dfe          	% degrees of freedom
        demographics    % subject demographics
        probe           % probe geometry
        
        tails = 'both';
        pcrit = 0.05;
        qcrit = 0.05;
    end
    
    properties ( Dependent = true )
        tstat
        
        tcrit
        tcrit_fdr

        p
        q
    end
    
    methods
        % t statistic calculation
        function tstat = get.tstat( obj )
            tstat = zeros(size(obj.beta));
            for i = 1:size(obj.beta,2)
                tstat(:,i)  = obj.beta(:,i) ./ sqrt( diag(obj.covb(:,:,i)) );
            end
        end
        
        % p value calculation
        function p = get.p( obj )
            t = obj.tstat;
            
            if strcmpi(obj.tails,'pos')
                p = tcdf(-t, obj.dfe);
            elseif strcmpi(obj.tails,'neg')
                p = tcdf(t, obj.dfe);
            else
                p = 2*tcdf(-abs(t), obj.dfe);
            end
        end
        
        % q values
        function q = get.q( obj )
            q = reshape( nirs.math.fdr( obj.p(:) )', size(obj.p) );
        end
        
        % critical value of t
        function tcrit = get.tcrit( obj )
            if strcmpi(obj.tails,'both')
                tcrit = -tinv(obj.pcrit/2, obj.dfe);
            else
                tcrit = -tinv(obj.pcrit, obj.dfe);
            end
        end
        
        function tcrit = get.tcrit_fdr( obj )
            % sorted p
            p = obj.p(:);
            [p, i] = sort(p);
            
            % corresponding q
            q = obj.q(i);
            
            idx = find( q(:) > obj.qcrit, 1 );
            
            % corrected pcrit
            pcrit = p(idx-1);
            
            if strcmpi(obj.tails,'both')
                tcrit = -tinv(pcrit/2, obj.dfe);
            else
                tcrit = -tinv(pcrit, obj.dfe);
            end
        end
    
        % linear transform of variables
        function S = ttest(obj, C, b)
            % test hypothesis that C*beta = b
            
            if nargin < 3
                b = zeros(size(C,1),1);
            end
            
            % transform beta
            beta = bsxfun(@minus, C*obj.beta, b);
            
            % calculate new covariance
            for i = 1:size(beta,2)
                covb(:,:,i) = C*obj.covb(:,:,i)*C';
                tstat(:,i)  = beta(:,i) ./ sqrt( diag(covb(:,:,i)) );
            end
            
            S = obj;
            
            S.beta  = beta;
            S.covb  = covb;
            S.names = obj.transformNames(C);
        end
        
        function S = ftest(obj, m)
            % this uses Hotelling's T squared test for joint 
            % hypothesis testing
            
            if nargin == 1
                m = ones(size(obj.beta,1),1) > 0;
            end
            
            if ~islogical(m)
                m = m > 0;
                warning('Converting mask to true/false.')
            end
                        
            n = obj.dfe;
            k = size(obj.beta,1);
            
            for i = 1:size(obj.beta,2)
                b = m(:) .* obj.beta(:,i);
                T2(i,1)     = b'*pinv(obj.covb(:,:,i))*b;
                F(i,1)      = (n-k) / k / (n-1) * T2(i);
            end
            
            S = nirs.AnovaStats();
            S.names = {strjoin( obj.names(m)', ' & ' )};
            S.F   = F';
            S.df1 = k;
            S.df2 = n-k;
            S.probe = obj.probe;
        end
        
        function tbl = roiAverage( obj, R, names )
            if ischar( names )
                names = {names};
            end
            
            varnames = {'ROI', 'Contrast', 'Beta', 'SE', 'DF', 'T', 'p'};
            tbl = table({},[],[],[],[],[],[], 'VariableNames', varnames);
            
            R = R > 0;
            
            for i = 1:size(R,1)
                for j = 1:size(obj.beta, 1)
                    roi     = names{i};
                    con     = obj.names{j};
                    
                    w       = 1./squeeze( obj.covb(j,j,R(i,:)) );
                    x       = ones(size(w));
                    
                    ix      = pinv( x'*diag(w)*x ) * x' * diag(w);
                    
                    beta    = ix * obj.beta(j,R(i,:))';
                    se      = sqrt( pinv( x'*diag(w)*x ) );
                    
                    
                    df      = obj.dfe;
                    t       = beta / se;
                    p       = 2*tcdf(-abs(t),df);
                
                    tmp = cell2table({roi, con, beta, se, df, t, p});
                    tmp.Properties.VariableNames = varnames;
                    tbl = [tbl; tmp];
                end
            end
        end
        
        function h = draw( obj, vtype, vrange )
            % type is either beta or tstat
            if nargin < 2
                vtype = 'T';
            end
            
            if lower(vtype(1)) == 'b'
                values = obj.beta;
                values( obj.p > obj.pcrit ) = 0;
                vcrit = 0;
            elseif lower(vtype(1)) == 't'
                values  = obj.tstat;
                vcrit   = obj.tcrit;
            end
            
            % range to show
            if nargin < 3
                vmin = min( values(:) );
                vmax = max( values(:) );
                
                if strcmpi( obj.tails, 'both' )
                    vrange = ceil( max( abs( [vmin vmax] ) ) );
                    vrange = [-vrange vrange];
                elseif strcmpi( obj.tails, 'pos' )
                    vrange = [0 ceil( vmax )];
                elseif strcmpi( obj.tails, 'neg' )
                    vrange = [-floor(vmin) 0];
                end
            end
            
            % loop through var names
            h = []; % handles
            types = obj.probe.link.type;
            
            if any(isnumeric(types))
                types = cellfun(@(x) {num2str(x)}, num2cell(types));
            end
            
            utypes = unique(types, 'stable');
            
            for iName = 1:length( obj.names )
                
                for iType = 1:length(utypes)
                    lst = strcmp( types, utypes(iType) );
                    
                    h(end+1) = figure;
                    v = values(iName, lst);
                    obj.probe.draw( v, vrange, vcrit );
                    title([utypes(iType) ' : ' obj.names{iName}], 'Interpreter','none')
                end
            end
        end
    end
    
    methods (Access = protected)
        % this function generates new names based on a linear tranformation
        % T of the variables
        function newNames = transformNames( obj, T )
            names = obj.names;
            for i = 1:size(T,1)
                newNames{i} = '';
                for j = 1:size(T,2)
                    c = T(i,j);
                    if c == 1
                        newNames{i} = [newNames{i} '+' names{j}];
                    elseif c == -1
                        newNames{i} = [newNames{i} '-' names{j}];
                    elseif c > 0
                        newNames{i} = [newNames{i} '+' num2str(c) names{j}];
                    elseif c < 0
                        newNames{i} = [newNames{i} num2str(c) names{j}];
                    end
                end
                
                if newNames{i}(1) == '+'
                    newNames{i} = newNames{i}(2:end);
                end
            end
            
            newNames = newNames(:);

        end
    end
  
end

