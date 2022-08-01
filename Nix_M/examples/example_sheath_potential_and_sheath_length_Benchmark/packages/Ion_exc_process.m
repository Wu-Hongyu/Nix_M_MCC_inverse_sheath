function [accur_post_v] = Ion_exc_process(order,vp,qm_ratio,excThresh)
%ION_ELA_PROCESS �˴���ʾ�йش˺�����ժҪ
%   �˴���ʾ��ϸ˵��
if ~isempty(vp)
    EineV=@(v,q_m_ratio) (v(:,1).^2+v(:,2).^2+v(:,3).^2)/(2*abs(q_m_ratio));%�ٶȱ�����
    E_loss=[excThresh{1,1}{1,order}]';
    E=EineV(vp,qm_ratio);
    E_remain=E-E_loss;
    
    v_inc=vp(:,:).*sqrt(E_remain./E);
    
    v_value=sqrt(v_inc(:,1).^2+v_inc(:,2).^2+v_inc(:,3).^2);%�ٶ�ģֵ
%     EineV=@(v,q_m_ratio) (v(:,1).^2+v(:,2).^2+v(:,3).^2)/(2*abs(q_m_ratio));%�ٶȱ�����
%     switch react
%         case 'Hp'
%             E=EineV(vp(:,:),constants.q_m_ratio_Hp);%����������ײ�����ӵ���������
%         case 'H2p'
%             E=EineV(vp(:,:),constants.q_m_ratio_H2p);%����������ײ�����ӵ���������
%     end
    cost=sqrt(rand(length(vp(:,1)),1));
    sint=sqrt(1-cost.^2);
    p=2*pi*rand(length(vp(:,1)),1);%�ս����0~2pi
    cosp=cos(p);
    sinp=sin(p);
    
    v_vertical=sqrt(vp(:,1).^2+vp(:,2).^2);%���Ի�2-36  2-37
    dvx=vp(:,1)./v_vertical.*vp(:,3).*sint.*cosp-vp(:,2)./v_vertical.*v_value.*sint.*sinp-vp(:,1).*(1-cost);
    dvy=(vp(:,2)./v_vertical.*vp(:,3).*sint.*cosp+vp(:,1)./v_vertical.*v_value.*sint.*sinp-vp(:,2).*(1-cost));
    dvz=-v_vertical.*sint.*cosp-vp(:,3).*(1-cost);
    accur_post_v=(vp(:,:)+[dvx dvy dvz]);
else
    accur_post_v=[];
end
end
