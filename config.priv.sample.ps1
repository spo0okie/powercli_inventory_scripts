#����� REST API ������� ��������������
$inventory_RESTapi_URL="https://inventory.domain.local/web/api"
#������ ��� ��� ����� ����������
$vCentersList=@(
	@{node='chl-vcenter.domain.local';	login='administrator@vsphere.local';	password='vcenter_user_pass'};
	@{node='msk-esxi1.domain.local';	login='root';							password='esxi_node_pass'};
	@{node='spb-vcenter.domain.local';	login='DOMAIN\inventory_vmware';		password='domain_user_pass'};
)
#������ �������� ������ � inventory (����� ��������� false ����� ������� "����� ������")
$write_inventory=$true
