Huawei AC6605 Access-Controler  AP state check
============================================
	Run huawei_ac6605_getap.pl from cron it will gets all AP from AC

	huawei_ac6605_checkap.pl - checks AP state in AC based on data from .json file 

Example
=======
	./huawei_ac6605_checkap.pl -H 172.99.19.2 -C foobar -I 172.99.12.21
	AP: ap-99 MAC: 48:46:fb:88:bd:a0 TYPE: AP6510DN-AGN STATE: normal REGION:2  -  OK
		
