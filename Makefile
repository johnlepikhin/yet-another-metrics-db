
all: out/collect-metrics out/dump-metrics out/register-metrics out/sensor-df.pl out/sensor-interrupts.pl out/sensor-loadavg.pl \
	out/sensor-meminfo.pl out/sensor-processes.pl out/http-server-metrics out/second-cron out/run-one

clean:
	rm -f out/*

out/collect-metrics:
	pp -P -I ./lib -o out/collect-metrics collect-metrics.pl

out/dump-metrics:
	pp -P -I ./lib -o out/dump-metrics dump-metrics.pl

out/register-metrics:
	pp -P -I ./lib -o out/register-metrics register-metrics.pl

out/http-server-metrics:
	pp -P -I ./lib -o out/http-server-metrics http-server-metrics.pl


out/sensor-df.pl:
	pp -P -I ./lib -o out/sensor-df.pl sensors/sensor-df.pl

out/sensor-interrupts.pl:
	pp -P -I ./lib -o out/sensor-interrupts.pl sensors/sensor-interrupts.pl

out/sensor-loadavg.pl:
	pp -P -I ./lib -o out/sensor-loadavg.pl sensors/sensor-loadavg.pl

out/sensor-meminfo.pl:
	pp -P -I ./lib -o out/sensor-meminfo.pl sensors/sensor-meminfo.pl

out/sensor-processes.pl:
	pp -P -I ./lib -o out/sensor-processes.pl sensors/sensor-processes.pl

out/second-cron:
	cp utils/second-cron out/

out/run-one:
	cp utils/run-one out/

dist: all
	mkdir -p dist
	tar czpf dist/metrics.tar.gz -C out .

install: clean all
	install out/collect-metrics ~/bin/
	install out/dump-metrics ~/bin/
	install out/register-metrics ~/bin/
	install out/http-server-metrics ~/bin/
	install utils/second-cron ~/bin/
#	install -m 644 -D datainfo.ini ~/.metrics/config.ini

