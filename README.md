Huawei AC6605 Access-Controler  AP state check
============================================
	Run huawei_ac6605_getap.pl from cron it will gets all AP from AC
	JSON file is used by checkap to speed up searching based on IP 

	huawei_ac6605_checkap.pl - AP provisioning state in AC
				 - Connected Users to AP
				 - The temperature of AP


Example
=======
	./huawei_ac6605_checkap.pl -H 172.99.19.2 -C foobar -I 172.99.12.21
	AP: ap-99 MAC: 48:46:fb:88:bd:a0 TYPE: AP6510DN-AGN STATE: normal REGION:2  -  OK

	./huawei_ac6605_checkap.pl -H 172.99.19.2 -C foobar  -0 -I 172.99.12.81 -w 5,20 -x 10,22
	AP: ap-52 MAC: f8:4a:bf:f1:28:c0 SN: 210235998899DB000819 TYPE: AP6510DN-AGN STATE: normal REGION:2 TEMP(WARN!!):22 USERCOUNT(WARN!!):12
	
