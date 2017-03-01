
compile-perl:
	pp -P -I ./ -o out/collect-metrics collect-metrics.pl
	pp -P -I ./ -o out/dump-metrics dump-metrics.pl
