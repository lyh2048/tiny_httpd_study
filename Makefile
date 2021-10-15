LIBS = -pthread
httpd: httpd.c
	gcc -g -W -Wall $(LIBS) -o httpd httpd.c
clean:
	rm httpd