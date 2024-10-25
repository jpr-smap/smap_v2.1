function tt=templates_gpu(obj,qref,dfs,varargin);
% % function tt=templates_gpu(obj,qref,dfs,varargin);
% % varargin may be an image. If specified, xcorrs are calculated and a
% vector of [peakVals peakLocs] is returned instead of templates

global SPV;
global ccMode;
global xyz V_Fr V_Fi Npix;

imref=[]; edgeSize=[]; ccMode=[];
if( nargin>3 )
    imref=varargin{1};
    if( nargin>4 )
        ccMode=varargin{2};
        %edgeSize=varargin{2};
    end;
end;

%%
if( strcmp(class(qref),'quaternion') )
    qref=squeeze(RotationMatrix(qref));
end;

fileNums=1:size(qref,3);

oneDfFlag=0;
if( isempty(dfs)==1 )
    method='exitWave';
else
    method='detectorIntensity';
    if( size(qref,3)>size(dfs,1) )
        %disp(['using one defocus only: [' num2str(dfs(1,1)) ' '  num2str(dfs(1,2)) ' ' num2str(dfs(1,3)) ']']);
        oneDfFlag=1;
    end;
end;


nWorkers=1;
if( length(fileNums)<nWorkers )
    nWorkers=length(fileNums);
end;
nGpus=1;
gpuIDs=[1];% 2 3 4]


targetProfileInd=[];
% if( nWorkers<=8 )
%     tempProfiles=parallel.clusterProfiles;
%     for j=1:length(tempProfiles)
%         if( findstr(tempProfiles{j},'profile_8')==1 )
%             targetProfileInd=j;
%             break
%         end;
%     end;
%     if( isempty(targetProfileInd)==1 )
%         myProfile=parallel.importProfile('/groups/denk/home/rickgauerj/Documents/MATLAB/file_profile_8.settings');
%         parallel.defaultClusterProfile('profile_8');
%     else
%         parallel.defaultClusterProfile(tempProfiles{targetProfileInd});
%     end;
% elseif( nWorkers>8 )
%     tempProfiles=parallel.clusterProfiles;
%     for j=1:length(tempProfiles)
%         if( findstr(tempProfiles{j},'profile_16')==1 )
%             targetProfileInd=j;
%             break
%         end;
%     end;
%     if( isempty(targetProfileInd)==1 )
%         myProfile=parallel.importProfile('/groups/denk/home/rickgauerj/Documents/MATLAB/file_profile_16.settings');
%         parallel.defaultClusterProfile('profile_16');
%     else
%         parallel.defaultClusterProfile(tempProfiles{targetProfileInd});
%     end;
% end;

gpuNum=ceil([1:nWorkers]./(nWorkers./nGpus));
gpuNum=gpuIDs(gpuNum);
%parpool('local',nWorkers);
% tempvar=matlabpool('size');
% if( (tempvar==0) )
%     matlabpool('local',nWorkers);
% elseif( tempvar~=nWorkers )
%     matlabpool close;
%     matlabpool('local',nWorkers);
% end;

%size(qref)
%size(dfs)
tt_temp=t_gpu(obj,qref,dfs,imref);
tt=tt_temp;
if( size(tt,2)==2 )
    tt=squeeze(tt)';
end;

%%

function outref=t_gpu(obj,qref,dfs,varargin);

global SPV;
global ccMode;
global xyz V_Fr V_Fi Npix;

ccFlag=0; edgeSize=[];
if( nargin>3 )
    if( ~isempty(varargin{1}) )
        ccFlag=1;
        imref=varargin{1};
        if( nargin>4 )
            ccMode=varargin{2};
        end;
    end;
    
%     if( nargin>6 )
%         edgeSize=varargin{4};
%     end;
end;

if( isempty(dfs)==1 )
    method='exitWave';
else
    method='detectorIntensity';
    ppmFlag=0;
    if( ~isempty(strfind(dfs(1,:),'PPM')) )
        ppmFlag=1;
    end;
end;

if( strcmp(class(qref),'quaternion') )
    qref=squeeze(RotationMatrix(qref));
end;


%F_abs=0.01
F_abs=0;

words='templates';
switch method
    case 'detectorIntensity'
        
        nTemplates=size(qref,3);
        
%        disp(['computing ' num2str(max([nTemplates,size(dfs,1)])) ' templates (' datestr(now) ')']);
        if( (max([nTemplates,size(dfs,1)]))==1 )
            words='template';
        end;
        fprintf('computing %s %s (%s)...',num2str(max([nTemplates,size(dfs,1)])),words,datestr(now));
        baseDir='~/matching/';
        
        % flips CTFFind astigmatism:
        if( size(dfs,2)==3 )
            %dfs(:,3)=-dfs(:,3); % 052417
        end;
        params.df=dfs;
        params.envFlag=1;
        params.MTF=[0 0.935 0 0 0.64];
        params.aPerPix=obj.prop.nmPerPixel_SP*10;
        nDfs=size(params.df,1);
        if( nDfs>nTemplates )
            fprintf('using one orientation at %d defocus values...',nDfs);
            for j=1:nDfs
                qref(:,:,j)=qref(:,:,1);
            end;
            nTemplates=nDfs;
        end;
        
        % read in the scattering potential and forward transform (leave origin at center):
        
        try
            assert( size(SPV,1)>0 );
            assert( size(xyz,1)>0 );
            assert( size(V_Fr,1)>0 );
        catch
            fprintf(['reading in scattering potential for ' obj.ID.ID '...\n']);
            SPV=gpuArray(smap.ri(smap.checkBaseDir(obj.prop.SPName)));

            Npix=size(SPV,1);

            [k_2d,centerPixel]=smap.getKs(zeros(Npix,Npix),params.aPerPix);
            [x,y,z]=meshgrid(1:Npix,1:Npix,1:Npix);
            cp=floor(Npix./2)+1;
            x0=x(:,:,cp)-cp;
            y0=y(:,:,cp)-cp;
            z0=zeros(Npix,Npix);
            
            %         % % ewald correction:
            %         k_ny=k_2d(cp,end);
            %         x0_temp=x0.*k_ny./cp;%max(abs(x0(cp,:)));
            %         y0_temp=y0.*k_ny./cp;%max(abs(y0(:,cp)));
            %         temp=smap.def_consts();
            %         V=temp.V; %300e3;
            %         %V=1e6;
            %         m_e = 9.10938215e-31; % kg
            %         lambda = temp.h/sqrt(temp.q_e*V*m_e*(temp.q_e/m_e*V/temp.c^2 + 2 ));
            %         lambda=lambda.*1e10;
            %         Rmax=(1./lambda).*params.aPerPix;
            %         z0=real(Rmax-sqrt((Rmax.^2)-(x0_temp.^2+y0_temp.^2)));
            %         z0=z0.*cp./k_ny;
            %         max(z0(:));
            
            xyz=[x0(:) y0(:) z0(:)];
            xyz_temp=[x0(:) y0(:) z0(:)];
            clear x y z;
            
            %        V=SPV;
            %        V_F=fftshift(fftn(ifftshift(V)));
            V=SPV+1i*F_abs*SPV;
            V_F=fftshift(fftn(ifftshift(V)));
            V_F(cp,cp,cp)=0;
            
            V_Fr=gpuArray(single(real(V_F)));
            V_Fi=gpuArray(single(imag(V_F)));
            
            xyz=gpuArray(xyz_temp);

        end;
        
        if( ~isempty(edgeSize) )
            SPV=smap.cutj(SPV,[edgeSize,edgeSize,edgeSize]);
        end;
        
        
        % compute the CTF(s) and MTF:
        
        if( nargin>3 )
            if( ~isempty(varargin{1}) )
                %params.envFlag=varargin{1};
            end;
            if( params.envFlag==0 )
                fprintf('no coherence envelope...');
            end;
            if( nargin>4 )
                if( ~isempty(varargin{2}) )
                    params.MTF=varargin{2};
                    fprintf(['using MTF with parameters:\n' num2str(params.MTF(1)) '\n' num2str(params.MTF(2)) '\n' num2str(params.MTF(3)) '\n' num2str(params.MTF(4)) '\n' num2str(params.MTF(5)) '\n']);
                end;
            end;
        end;
        MTF_binFactor=2;
        %MTF=smap.approxMTF(k_2d,params.MTF,MTF_binFactor);
        MTF=ones(Npix,Npix);
        
        CTF=zeros(Npix,Npix,nDfs);
        Npix_r=gather(Npix);
        
        if( ppmFlag==1 )
            MTFCTF=smap.makePhasePlate(zeros(Npix,Npix,'single'),'vulovic');
        else
%             params.envFlag
            CTF=smap.ctf(params.df,Npix_r);%,0.01);
%             CTF=smap.ctf(params.df,Npix_r,params.aPerPix,params.envFlag);%,0.01);
%             if( nDfs>1 )
%                 CTF=smap.ctf(params.df,Npix,params.aPerPix,params.envFlag,0,0);
%                     for i=1:nDfs
% %                        pause;
%                         %CTF(:,:,i)=smap.ctf(params.df(i,:),Npix,params.aPerPix,params.envFlag,0,0);                        
%                         MTFCTF(:,:,i)=gpuArray(single(MTF.*CTF(:,:,i)));
%                     end;
%             else
%                 CTF=smap.ctf(params.df,Npix,params.aPerPix,params.envFlag,0,0);
%                 MTFCTF=gpuArray(single(MTF.*CTF));
%             end;
            
        end;
                        
%         Npix_r=gather(Npix);
        Npix=gpuArray(Npix);        
%         dummyX=1:size(V_F,1); dummyY=1:size(V_F,2); dummyZ=1:size(V_F,3);
        dummyX=[1:Npix]; dummyY=[1:Npix]; dummyZ=[1:Npix];
        cp=floor(Npix./2)+1;
        
        if( 0 )
        % take normal 3D fft and lop off one half:
        V_Fr=real(V_F(1:cp,:,:));
        V_Fi=imag(V_F(1:cp,:,:));
        
        %-cut off interpolation grid:
        cp=floor(Npix./2)+1;
        [x,y,z]=meshgrid(1:Npix,1:cp,1:Npix);
        x0=x(1:cp,:,cp)-cp;
        y0=y(1:cp,:,cp)-cp;
        z0=zeros(cp,Npix);
        xyz=[x0(:) y0(:) z0(:)];
        
        pp_full=complex(zeros(Npix,Npix),zeros(Npix,Npix));
        output_image = complex(ba_interp3(double(V_Fr),X,Y,Z,'linear'),ba_interp3(double(V_Fi),X,Y,Z,'linear'));
        vi_rs=reshape(output_image,cp,Npix);
        vi_rs(find(isnan(vi_rs)==1))=0;
        projPot=vi_rs;
        pp_full(1:cp,:)=projPot;
        pp_full_r=real(pp_full);
        pp_full_i=imag(pp_full);
        pp_full_r(cp+1:end,:)=circshift(rot90(pp_full_r(2:cp-1,:),2),[0,1]);
        pp_full_i(cp+1:end,:)=-circshift(rot90(pp_full_i(2:cp-1,:),2),[0,1]);
        projPot=complex(pp_full_r,pp_full_i);
        
        ew=exp(1i.*(fftshift((ifftn(ifftshift(projPot))))));
        w_det=fftshift(ifftn(ifftshift(fftshift(fftn(ifftshift(ew))).*CTF)));
        template=w_det.*conj(w_det);
                
        end;

        
        
        if( ccFlag==1 )
            cp_im=floor(size(imref,1)./2)+1;
            R_forMask=single(smap.rrj(zeros(Npix_r,Npix_r)).*(floor(Npix_r./2)./0.5));
            rMask_temp=ones(size(R_forMask));
            rMask_temp(find(R_forMask>Npix_r/2))=nan;
            rMask=gpuArray(single(rMask_temp));
            
            % % calculate the expected value away from one unrotated template:
            X=xyz(:,1)+cp; Y=xyz(:,2)+cp; Z=xyz(:,3)+cp;
            output_image = interp3gpu(dummyX,dummyY,dummyZ,V_Fr,V_Fi,Y,X,Z);
            %interp3gpu(dummyX,dummyY,dummyZ,V_Fr,V_Fi,xyz_r(:,2)+cp,xyz_r(:,1)+cp,xyz_r(:,3)+cp);
            projPot=reshape(output_image,Npix,Npix);
            
            projPot=projPot+1i*F_abs*projPot;
            
            ew=exp(1i.*(fftshift((ifftn(ifftshift(projPot))))));
            %w_det=fftshift(ifftn(ifftshift(fftshift(fftn(ifftshift(ew))).*MTFCTF(:,:,1))));
            w_det=fftshift(ifftn(ifftshift(fftshift(fftn(ifftshift(ew))).*CTF(:,:,1))));
            template=w_det.*conj(w_det);
            temp=gather(rMask);
            temp(isnan(temp))=0;
            temp=1-temp; temp(temp==0)=nan;
            temp=gather(template).*temp;
            bgVal=gpuArray(single(nanmedian(temp(:))));
            
            %imref=smap.nm(smap.padForFFT(imref));
            imref=smap.nm(imref);
            
            fprintf('filtering...\n');
            [fPSD,imFilt,~]=smap.psdFilter(imref,'sqrt');
            imref_F=gpuArray(single(fftn(ifftshift(imFilt))));
            fPSD=ifftshift(fPSD);
                        
            xDim=size(imFilt,1); yDim=size(imFilt,2);
            
%             fPSD=ones(xDim,yDim);
%             imref_F=gpuArray(single(fftn(ifftshift(imref))));
            
            mip=gpuArray.ones(xDim,yDim,'single').*-1000;
            mipi=mip.*0;
            cc_cp=zeros(1,nTemplates);
            
            % % work out the shifts for padding templates out just once:
            oldDim=[(Npix) (Npix)]; oldDim=gather(oldDim);
            newDim=[(xDim) (yDim)];
            halfOldDim=[]; halfNewDim=[]; centerPixOld=[]; centerPixNew=[];
            for i=1:2
                oddOldFlag=mod(oldDim(i),2);
                if( oddOldFlag==1 )
                    halfOldDim(i)=ceil(oldDim(i)./2);
                    halfNewDim(i)=floor(newDim(i)./2);
                    centerPixOld(i)=halfOldDim(i);
                    centerPixNew(i)=halfNewDim(i)+1;
                else
                    halfOldDim(i)=oldDim(i)./2;
                    halfNewDim(i)=newDim(i)./2;
                    centerPixOld(i)=halfOldDim(i)+1;
                    centerPixNew(i)=floor(halfNewDim(i)+1);
                end;
                edges{i}=[centerPixOld(i)-newDim(i)./2 centerPixOld(i)+(newDim(i)./2)-1];
            end;
            diffSize=newDim(1)-oldDim(1);
            rowColInds={ [num2str(centerPixNew(1)-oldDim(1)./2) ':' num2str((centerPixNew(1)+oldDim(1)./2)-1)] , ...
                [num2str(centerPixNew(2)-oldDim(2)./2) ':' num2str((centerPixNew(2)+oldDim(2)./2)-1)] };
            dummy=reshape(1:(xDim)*(yDim),(xDim),(yDim));
            eval(['rowColNums=dummy(' rowColInds{1} ',' rowColInds{2} ');']);
            
            temp_image=gpuArray.zeros(xDim,yDim,'single');
            fullXY=gpuArray(xDim*yDim);
            Npix_im=xDim;
            
            %pv=gpuArray(zeros(nTemplates,1,'double'));
            %pl=gpuArray(zeros(nTemplates,1,'double'));
            %templates=zeros(1,2,nTemplates,'double');
            %templates=zeros(newDim(1),newDim(2),nTemplates,'single');
        else
            templates=zeros(Npix_r,Npix_r,nTemplates,'double');
        end;

%        pause; 
        tic;
        for i=1:nTemplates
            RM=qref(:,:,i)';%.*R_opt; % this preserves the old quaternion flip. R was calculated directly from hopf set

            
 
                    %For each proj:
        %-interp
        %-reshape
        %-rotj90 & duplicate
        %-ifft


%             vi_rs_full_r=zeros(length(dummyX_test),length(dummyY_test));
%             vi_rs_full_i=zeros(length(dummyX_test),length(dummyY_test));
% 
%             xyz_r=(RM*xyz_test')';
% %            xyz_r=xyz_r(find(xyz_r(:,3)>0),:);
% %            [~,inds]=sort(xyz_r(:,3),'descend');
% %            xyz_r=xyz_r(inds(1:61250),:);
%             %X=xyz_r(:,1)+cp; Y=xyz_r(:,2)+cp; Z=xyz_r(:,3)+cp;
%             X=xyz_r(:,1)+cp; Y=xyz_r(:,2)+cp; Z=xyz_r(:,3);
% 
%             output_image=complex(interpn(dummyX_test,dummyY_test,dummyZ_test,V_Fr,Y,X,Z), ...
%                 interpn(dummyX_test,dummyY_test,dummyZ_test,V_Fi,Y,X,Z));
%             vi_rs=reshape(output_image,cp,Npix);
% %            vi_rs=reshape(output_image,Npix,Npix)';
%             vi_rs(find(isnan(vi_rs)==1))=0;
%             vi_rs_full_r(1:cp,:)=real(gather(vi_rs));
%             vi_rs_full_i(1:cp,:)=imag(gather(vi_rs));
%             temp=circshift(vi_rs_full_r,[-1,-1]);            
%             vi_rs_full_r((cp):end,:)=fliplr(flipud(temp(1:cp-1,:)));
%             temp=circshift(vi_rs_full_i,[-1,-1]);
%             vi_rs_full_i((cp):end,:)=-fliplr(flipud(temp(1:cp-1,:)));
%             
%             
% 
%             
%             projPot=vi_rs_full_r+1i*F_abs*vi_rs_full_i;
            
% % % sinc?:    
%     xyz_r=(RM*xyz')';
%     temp=sqrt(sum((xyz_r-round(xyz_r)).^2,2));
%     box_here=gather(sinc(temp));
%     xyz_r=round(xyz_r)+cp;
%     inds=find(xyz_r(:,1) > 0 & xyz_r(:,2)>0 & xyz_r(:,3)>0 & ...
%         xyz_r(:,1)<=Npix & xyz_r(:,2)<=Npix & xyz_r(:,3)<=Npix);
%     xyz_r=xyz_r(inds,:);
%     box_here=box_here(inds);
%      
%     inds_w=sub2ind(Npix.*[1 1 1],xyz_r(:,2),xyz_r(:,1),xyz_r(:,3));    
%     temp_r=gpuArray.zeros(Npix,Npix); temp_i=temp_r;
%     temp_r(inds)=V_Fr(inds_w).*(box_here(:));
%     temp_i(inds)=V_Fi(inds_w).*(box_here(:));
%     vi_rs=complex(temp_r,temp_i);
%     projPot=vi_rs+1i*F_abs*vi_rs;
    
% linear:
           xyz_r=(RM*xyz')';
           X=xyz_r(:,1)+cp; Y=xyz_r(:,2)+cp; Z=xyz_r(:,3)+cp;            
           output_image=complex(interpn(dummyX,dummyY,dummyZ,V_Fr,xyz_r(:,2)+cp,xyz_r(:,1)+cp,xyz_r(:,3)+cp,'linear',0), ...
               interpn(dummyX,dummyY,dummyZ,V_Fi,xyz_r(:,2)+cp,xyz_r(:,1)+cp,xyz_r(:,3)+cp,'linear',0));
           %output_image=interp3gpu(dummyX,dummyY,dummyZ,V_Fr,V_Fi,Y,X,Z);

           %ew=exp(1i.*(fftshift((ifftn(ifftshift(projPot))))));
           %w_det=fftshift(ifftn(ifftshift(fftshift(fftn(ifftshift(ew))).*MTFCTF(cp:end,:))));
           %template=w_det.*conj(w_det);
           
           vi_rs=reshape(output_image,Npix,Npix);
           %vi_rs(find(isnan(vi_rs)==1))=0;
           projPot=vi_rs+1i*F_abs*vi_rs;
           
           %pause;
           
            % multiply by the aberration function, compute detector intensity, apply MTF:
            if( nDfs>1 )
%                 ew=exp(1i.*(fftshift((ifftn(ifftshift(projPot))))));
%                 %w_det=fftshift(ifftn(ifftshift(fftshift(fftn(ifftshift(ew))).*MTFCTF(:,:,i))));
%                 w_det=fftshift(ifftn(ifftshift(fftshift(fftn(ifftshift(ew))).*CTF(:,:,i))));
%                 template=w_det.*conj(w_det);
        
                
                        template=1+2.*(fftshift(real(ifftn(ifftshift(imag(CTF(:,:,i)).*projPot)))));
                        
            else
                %pause;
           
%                 ew=exp(1i.*(fftshift((ifftn(ifftshift(projPot))))));
%                 %w_det=fftshift(ifftn(ifftshift(fftshift(fftn(ifftshift(ew))).*MTFCTF)));
%                 w_det=fftshift(ifftn(ifftshift(fftshift(fftn(ifftshift(ew))).*CTF)));
%                 template=w_det.*conj(w_det);

                template=1+2.*(fftshift(real(ifftn(ifftshift(imag(CTF).*projPot)))));

%                 template=smap.iftj(projPot.*imag(CTF));
                

                %        template=1+2.*(fftshift(real(ifftn(ifftshift(MTFCTF.*projPot)))));
                

                %template=imag(fftshift(ifftn(ifftshift(MTFCTF.*projPot))));

                
            end;
            if( ccFlag==1 )
                template=template-bgVal;
                temp_image(rowColNums)=template;
                template_F=fftn(ifftshift(temp_image));
                
                template_F=template_F.*fPSD;
                templateVec=template_F(:);
                v=sum(abs(templateVec).^2,1,'double');
                v=v./fullXY;
                template_F=template_F./sqrt(v./fullXY);
                template_F=conj(template_F);
                
                cc_F=arrayfun(@times,imref_F,template_F);
                cc=fftshift(ifftn(cc_F));
                cc=real(cc);
                cc=cc./Npix_im;                

                cc_cp(i)=gather(cc(cp_im,cp_im));
                
                inds=(cc>mip);
                mip(inds)=(cc(inds));
                mipi(inds)=i;

                %pause;
                
                %[pv(i),pl(i)]=max(cc(:));
                %templates(:,:,i)=gather(cc);
                %templates(:,1:2,i)=gather([pv(i) pl(i)]);

            else
                % % surprise: it is not the gathering or assignment that
                % takes time, but apparently the recasting of double as
                % single
%                 trash=gather(template);
                templates(:,:,i)=gather(template);
%                templates(:,:,i)=gather(template);
%                templates(:,:,i)=zeros(395,395,'single');
            end;
            if( mod(i,100)==0 )
                fprintf('%d/%d\n',i,nTemplates);%length(qref));
            end;
        end;
%         toc
        if( ccFlag )
            if( ~isempty(ccMode) )
                    outref=cc_cp;
            else
                outref=cat(3,gather(mip),gather(mipi));
            end;

            else
            outref=(templates);
        end;
        
        Npix=gather(Npix);
%        disp(['done (' datestr(now) ')']);
        fprintf('done (%s)\n',datestr(now));
    case 'exitWave'
        
                nTemplates=size(qref,3);
        
        if( (max([nTemplates,size(dfs,1)]))==1 )
            words='template';
        end;
        %disp(['computing ' num2str(max([nTemplates,size(dfs,1)])) ' templates (' datestr(now) ')']);
        fprintf('computing %s %s (%s)...',num2str(max([nTemplates,size(dfs,1)])),words,datestr(now));
        
        params.envFlag=1;
        params.MTF=[0 0.935 0 0 0.64];
        params.aPerPix=obj.prop.nmPerPixel_SP*10;
        
        % read in the scattering potential and forward transform (leave origin at center):
        fprintf(['reading in scattering potential for ' obj.ID.ID '...\n']);
        SPV=gpuArray(smap.ri(smap.checkBaseDir(obj.prop.SPName)));
        %SPV=(smap.ri(smap.checkBaseDir(obj.prop.SPName)));
        if( ~isempty(edgeSize) )
            SPV=smap.cutj(SPV,[edgeSize,edgeSize,edgeSize]);
        end;
        %SPV=smap.extendj(SPV,648.*[1,1,1],mode(SPV(:)));
        Npix=size(SPV,1);
                
        % [k_1d,k_2d,cp,xd,yd]=smap.getKs(Npix,params.aPerPix);
        [k_2d,centerPixel]=smap.getKs(zeros(Npix,Npix),params.aPerPix);
        % [k_1d,k_2d,cp,xd,yd]=getKs(Npix,params.aPerPix);
        [x,y,z]=meshgrid(1:Npix,1:Npix,1:Npix);
        cp=floor(Npix./2)+1;
        x0=x(:,:,cp)-cp;
        y0=y(:,:,cp)-cp;
        z0=zeros(Npix,Npix);
        
%         % % ewald correction:
%         k_ny=k_2d(cp,end);
%         x0_temp=x0.*k_ny./cp;%max(abs(x0(cp,:)));
%         y0_temp=y0.*k_ny./cp;%max(abs(y0(:,cp)));
%         temp=smap.def_consts();        
%         V=temp.V; %300e3;
%         %V=1e6;
%         m_e = 9.10938215e-31; % kg
%         lambda = temp.h/sqrt(temp.q_e*V*m_e*(temp.q_e/m_e*V/temp.c^2 + 2 ));
%         lambda=lambda.*1e10;        
%         Rmax=(1./lambda).*params.aPerPix;
%         z0=real(Rmax-sqrt((Rmax.^2)-(x0_temp.^2+y0_temp.^2)));
%         z0=z0.*cp./k_ny;
%         max(z0(:))
        
        xyz=[x0(:) y0(:) z0(:)];
        xyz_temp=[x0(:) y0(:) z0(:)];
        clear x y z;
        
%         V=SPV;
%         V_F=fftshift(fftn(ifftshift(V)));
        
        V=SPV+1i*F_abs*SPV;
        clear SPV;
        V_F=fftshift(fftn(ifftshift(V)));
        V_F(cp,cp,cp)=0;

        clear V;

        V_Fr=gpuArray(single(real(V_F)));
        V_Fi=gpuArray(single(imag(V_F)));

        R_opt=[1     1    -1
            1     1    -1
            -1     -1     1];
                        
        xyz=gpuArray(xyz_temp);
        Npix_r=Npix;
        Npix=gpuArray(Npix);
                
        dummyX=1:size(V_F,1); dummyY=1:size(V_F,2); dummyZ=1:size(V_F,3);
        
        if( ccFlag==1 )
            R_forMask=single(smap.rrj(zeros(Npix,Npix)).*(floor(Npix./2)./0.5));
            rMask_temp=ones(size(R_forMask));
            rMask_temp(find(R_forMask>Npix_r/2))=nan;
            rMask=gpuArray(single(rMask_temp));
            
            % % calculate the expected value away from one unrotated template:
            X=xyz(:,1)+cp; Y=xyz(:,2)+cp; Z=xyz(:,3)+cp;
            output_image = interp3gpu(dummyX,dummyY,dummyZ,V_Fr,V_Fi,Y,X,Z);
            
            projPot=reshape(output_image,Npix,Npix);
            projPot=projPot+1i*F_abs*projPot;
                        
            ew=exp(1i.*(fftshift(real(ifftn(ifftshift(projPot))))));
            w_det=fftshift(ifftn(ifftshift(fftshift(fftn(ifftshift(ew))).*MTFCTF)));
            template=w_det.*conj(w_det);
            temp=gather(rMask);
            temp(isnan(temp))=0;
            temp=1-temp; temp(temp==0)=nan;
            temp=gather(template).*temp;
            bgVal=gpuArray(single(nanmedian(temp(:))));
            
            imref=smap.nm(smap.padForFFT(imref));
            
            [fPSD,imFilt,~]=smap.psdFilter(imref,'sqrt');
            imref_F=gpuArray(single(fftn(ifftshift(imFilt))));
            
            xDim=size(imFilt,1); yDim=size(imFilt,2);
            
            % % work out the shifts for padding templates out just once:
            oldDim=[(Npix) (Npix)]; oldDim=gather(oldDim);
            newDim=[(xDim) (yDim)];
            halfOldDim=[]; halfNewDim=[]; centerPixOld=[]; centerPixNew=[];
            for i=1:2
                oddOldFlag=mod(oldDim(i),2);
                if( oddOldFlag==1 )
                    halfOldDim(i)=ceil(oldDim(i)./2);
                    halfNewDim(i)=floor(newDim(i)./2);
                    centerPixOld(i)=halfOldDim(i);
                    centerPixNew(i)=halfNewDim(i)+1;
                else
                    halfOldDim(i)=oldDim(i)./2;
                    halfNewDim(i)=newDim(i)./2;
                    centerPixOld(i)=halfOldDim(i)+1;
                    centerPixNew(i)=floor(halfNewDim(i)+1);
                end;
                edges{i}=[centerPixOld(i)-newDim(i)./2 centerPixOld(i)+(newDim(i)./2)-1];
            end;
            diffSize=newDim(1)-oldDim(1);
            rowColInds={ [num2str(centerPixNew(1)-oldDim(1)./2) ':' num2str((centerPixNew(1)+oldDim(1)./2)-1)] , ...
                [num2str(centerPixNew(2)-oldDim(2)./2) ':' num2str((centerPixNew(2)+oldDim(2)./2)-1)] };
            dummy=reshape(1:(xDim)*(yDim),(xDim),(yDim));
            eval(['rowColNums=dummy(' rowColInds{1} ',' rowColInds{2} ');']);
            
            temp_image=gpuArray.zeros(xDim,yDim,'single');
            fullXY=gpuArray(xDim*yDim);
            Npix_im=xDim;
            
            pv=gpuArray(zeros(nTemplates,1,'single'));
            pl=gpuArray(zeros(nTemplates,1,'single'));
            
            %templates=zeros(newDim(1),newDim(2),nTemplates,'single');
        else
            templates=zeros(Npix_r,Npix_r,nTemplates,'double');
            
        end;
        
        for i=1:nTemplates
            RM=qref(:,:,i)';%.*R_opt; % this preserves the old quaternion flip. R was calculated directly from hopf set
            
% % % sinc?:    
%     xyz_r=(RM*xyz')';
%     temp=sqrt(sum((xyz_r-round(xyz_r)).^2,2));
%     box_here=gather(sinc(temp));
%     xyz_r=round(xyz_r)+cp;
%     inds=find(xyz_r(:,1) > 0 & xyz_r(:,2)>0 & xyz_r(:,3)>0 & ...
%         xyz_r(:,1)<=Npix & xyz_r(:,2)<=Npix & xyz_r(:,3)<=Npix);
%     xyz_r=xyz_r(inds,:);
%     box_here=box_here(inds);
%      
%     inds_w=sub2ind(Npix.*[1 1 1],xyz_r(:,2),xyz_r(:,1),xyz_r(:,3));    
%     temp_r=gpuArray.zeros(Npix,Npix); temp_i=temp_r;
%     temp_r(inds)=V_Fr(inds_w).*(box_here(:));
%     temp_i(inds)=V_Fi(inds_w).*(box_here(:));
%     vi_rs=complex(temp_r,temp_i);
%     projPot=vi_rs+1i*F_abs*vi_rs;
    
% linear:
        
%            pause;
%            RM=normalizeRM(RotationMatrix(quaternion.eulerangles('xyz',[45 45 45])));

            xyz_r=(RM*xyz')';
            X=xyz_r(:,1)+cp; Y=xyz_r(:,2)+cp; Z=xyz_r(:,3)+cp;
            
            %     output_image = complex(ba_interp3(double(real(V_F)),X,Y,Z,'cubic'),ba_interp3(double(imag(V_F)),X,Y,Z,'cubic'));
            output_image=interp3gpu(dummyX,dummyY,dummyZ,V_Fr,V_Fi,xyz_r(:,2)+cp,xyz_r(:,1)+cp,xyz_r(:,3)+cp);
            vi_rs=reshape(output_image,Npix,Npix);
            vi_rs(find(isnan(vi_rs)==1))=0;
            %projPot=vi_rs;
            projPot=vi_rs+1i*F_abs*vi_rs;
            
            if( ccFlag==1 )
                template=template-bgVal;
                temp_image(rowColNums)=template;
                template_F=fftn(ifftshift(temp_image));
                
                template_F=template_F.*fPSD;
                templateVec=template_F(:);
                v=sum(abs(templateVec).^2,1,'double');
                v=v./fullXY;
                template_F=template_F./sqrt(v./fullXY);
                template_F=conj(template_F);
                
                cc_F=arrayfun(@times,imref_F,template_F);
                cc=fftshift(ifftn(cc_F));
                cc=real(cc);
                cc=cc./Npix_im;
                [pv(i),pl(i)]=max(cc(:));
                %templates(:,:,i)=gather(cc);
                templates(:,:,i)=gather([pv(i) pl(i)]);
            else
                templates(:,:,i)=gather(projPot);
            end;
            
            if( mod(i,10)==0 )
                fprintf('%d/%d\n',i,nTemplates);%length(qref));
            end;
        end;
        
        outref=single(templates);
        
        
        %disp(['done (' datestr(now) ')']);
        fprintf('done (%s)\n',datestr(now));
        
end;



%%
