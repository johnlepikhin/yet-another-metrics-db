
clean:
	rm out/*

out/collect-metrics:
	pp -P -I ./ -o out/collect-metrics collect-metrics.pl

out/dump-metrics:
	pp -P -I ./ -o out/dump-metrics dump-metrics.pl

out/register-metrics:
	pp -P -I ./ -o out/register-metrics register-metrics.pl

out/sensor-df.pl:
	pp -P -I ./ -o out/sensor-df.pl sensor-df.pl

out/sensor-interrupts.pl:
	pp -P -I ./ -o out/sensor-interrupts.pl sensor-interrupts.pl

out/sensor-loadavg.pl:
	pp -P -I ./ -o out/sensor-loadavg.pl sensor-loadavg.pl

out/sensor-meminfo.pl:
	pp -P -I ./ -o out/sensor-meminfo.pl sensor-meminfo.pl

out/sensor-processes.pl:
	pp -P -I ./ -o out/sensor-processes.pl sensor-processes.pl

out: out/collect-metrics out/dump-metrics out/register-metrics out/sensor-df.pl out/sensor-interrupts.pl out/sensor-loadavg.pl \
	out/sensor-meminfo.pl out/sensor-processes.pl

install: clean out
	install out/collect-metrics ~/bin/
	install out/dump-metrics ~/bin/
	install out/register-metrics ~/bin/
	install second-cron ~/bin/
#	install -m 644 -D datainfo.ini ~/.metrics/config.ini

