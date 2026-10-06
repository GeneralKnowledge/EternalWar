## System-level economy: production, consumption, prices, and job board.
## Inspired by Limit Theory's Economy component + Mine/Transport jobs.
class_name EconomySystem
extends RefCounted

const JOB_SAMPLE_REFRESH := 1.0

var jobs: Array = []
var last_refresh_time: float = -999.0
var metrics: Dictionary = {
	"avg_prices": {},
	"total_ore": 0.0,
	"total_metal": 0.0,
	"total_components": 0.0,
	"transactions": 0,
	"production_cycles": 0,
}


func tick(world: Dictionary, dt: float) -> void:
	_tick_production(world, dt)
	_tick_consumption(world, dt)
	_update_prices(world)
	if world["sim_time"] - last_refresh_time >= JOB_SAMPLE_REFRESH:
		_rebuild_jobs(world)
		_recompute_metrics(world)
		last_refresh_time = world["sim_time"]


func _tick_production(world: Dictionary, dt: float) -> void:
	for station in world["stations"]:
		for prod in station["productions"]:
			var recipe: Dictionary = Recipes.by_id(prod["recipe_id"])
			if recipe.is_empty():
				continue
			if not _can_afford(station, recipe["inputs"]):
				continue
			prod["progress"] = float(prod["progress"]) + dt
			var duration: float = float(recipe["duration"])
			while float(prod["progress"]) >= duration:
				if not _can_afford(station, recipe["inputs"]):
					prod["progress"] = 0.0
					break
				_consume(station, recipe["inputs"])
				_produce(station, recipe["outputs"])
				prod["progress"] = float(prod["progress"]) - duration
				metrics["production_cycles"] = int(metrics["production_cycles"]) + 1
				for item in recipe["inputs"]:
					station["flows"][item] = float(station["flows"].get(item, 0.0)) - float(recipe["inputs"][item]) / duration
				for item in recipe["outputs"]:
					station["flows"][item] = float(station["flows"].get(item, 0.0)) + float(recipe["outputs"][item]) / duration


func _tick_consumption(world: Dictionary, dt: float) -> void:
	# Stations burn energy/food proportional to population — creates demand sinks.
	for station in world["stations"]:
		var pop: float = float(station.get("population", 100.0))
		var energy_need := pop * 0.002 * dt
		var food_need := pop * 0.0015 * dt
		var e_have: float = float(station["inventory"].get(Commodities.ENERGY, 0.0))
		var f_have: float = float(station["inventory"].get(Commodities.FOOD, 0.0))
		var e_use := minf(e_have, energy_need)
		var f_use := minf(f_have, food_need)
		station["inventory"][Commodities.ENERGY] = e_have - e_use
		station["inventory"][Commodities.FOOD] = f_have - f_use
		if e_use < energy_need * 0.5 or f_use < food_need * 0.5:
			station["population"] = maxf(40.0, pop - 0.01 * dt)
		else:
			station["population"] = minf(400.0, pop + 0.005 * dt)


func _update_prices(world: Dictionary) -> void:
	for station in world["stations"]:
		for item in Commodities.ALL:
			var stock: float = float(station["inventory"].get(item, 0.0))
			var base := Commodities.base_price_of(item)
			# Scarcity raises price; surplus lowers it.
			var target := 80.0
			var ratio := clampf(stock / target, 0.05, 4.0)
			var price := base * (1.35 / sqrt(ratio))
			# Soft EMA toward target price.
			var prev: float = float(station["prices"].get(item, base))
			station["prices"][item] = lerpf(prev, price, 0.15)


func _rebuild_jobs(world: Dictionary) -> void:
	jobs.clear()
	var yields: Array = world["yields"]
	var stations: Array = world["stations"]

	# Mining jobs: each yield × each station that buys ore.
	for y in yields:
		if float(y["remaining"]) <= 0.0:
			continue
		for st in stations:
			var payout := SimEntities.station_buy_price(st, Commodities.ORE) * 40.0
			jobs.append({
				"type": "mine",
				"src_id": y["id"],
				"dst_id": st["id"],
				"item": Commodities.ORE,
				"payout": payout,
			})

	# Transport jobs: buy low at src, sell high at dst.
	for i in stations.size():
		var src: Dictionary = stations[i]
		for j in stations.size():
			if i == j:
				continue
			var dst: Dictionary = stations[j]
			for item in Commodities.ALL:
				var buy := SimEntities.station_sell_price(src, item)
				var sell := SimEntities.station_buy_price(dst, item)
				var edge := sell - buy
				if edge <= 1.0:
					continue
				if float(src["inventory"].get(item, 0.0)) < 5.0:
					continue
				jobs.append({
					"type": "transport",
					"src_id": src["id"],
					"dst_id": dst["id"],
					"item": item,
					"payout": edge * 30.0,
				})


func _recompute_metrics(world: Dictionary) -> void:
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	for c in Commodities.ALL:
		sums[c] = 0.0
		counts[c] = 0
	var total_ore := 0.0
	var total_metal := 0.0
	var total_components := 0.0
	for st in world["stations"]:
		for c in Commodities.ALL:
			sums[c] = float(sums[c]) + float(st["prices"].get(c, 0.0))
			counts[c] = int(counts[c]) + 1
			var inv: float = float(st["inventory"].get(c, 0.0))
			match c:
				Commodities.ORE:
					total_ore += inv
				Commodities.METAL:
					total_metal += inv
				Commodities.COMPONENTS:
					total_components += inv
	var avg: Dictionary = {}
	for c in Commodities.ALL:
		avg[c] = float(sums[c]) / maxf(1.0, float(counts[c]))
	metrics["avg_prices"] = avg
	metrics["total_ore"] = total_ore
	metrics["total_metal"] = total_metal
	metrics["total_components"] = total_components
	metrics["job_count"] = jobs.size()


func find_station(world: Dictionary, id: int) -> Dictionary:
	for st in world["stations"]:
		if int(st["id"]) == id:
			return st
	return {}


func find_yield(world: Dictionary, id: int) -> Dictionary:
	for y in world["yields"]:
		if int(y["id"]) == id:
			return y
	return {}


func sample_best_job(ship: Dictionary, rng: SeededRNG, iterations: int = 24) -> Dictionary:
	if jobs.is_empty():
		return {}
	var best: Dictionary = {}
	var best_payout := -1.0
	# Prefer class-appropriate work.
	var prefer_mine := int(ship["ship_class"]) == SimEntities.ShipClass.MINER
	var prefer_trade := int(ship["ship_class"]) == SimEntities.ShipClass.TRADER \
		or int(ship["ship_class"]) == SimEntities.ShipClass.HAULER
	for _i in iterations:
		var job: Dictionary = rng.choose(jobs)
		if job.is_empty():
			break
		var payout: float = float(job["payout"])
		if prefer_mine and job["type"] == "mine":
			payout *= 1.35
		if prefer_trade and job["type"] == "transport":
			payout *= 1.25
		if prefer_mine and job["type"] == "transport":
			payout *= 0.7
		if prefer_trade and job["type"] == "mine":
			payout *= 0.75
		# Distance penalty approx via later travel; light bias against huge payouts far away handled in AI.
		if payout > best_payout:
			best_payout = payout
			best = job
	return best.duplicate(true)


func sell_to_station(world: Dictionary, ship: Dictionary, station: Dictionary, item: String) -> float:
	var have: float = float(ship["cargo"].get(item, 0.0))
	if have <= 0.0:
		return 0.0
	var price := SimEntities.station_buy_price(station, item)
	var qty := SimEntities.remove_cargo(ship, item, have)
	var revenue := qty * price
	ship["credits"] = float(ship["credits"]) + revenue
	station["credits"] = float(station["credits"]) - revenue
	station["inventory"][item] = float(station["inventory"].get(item, 0.0)) + qty
	metrics["transactions"] = int(metrics["transactions"]) + 1
	return revenue


func buy_from_station(world: Dictionary, ship: Dictionary, station: Dictionary, item: String, max_amount: float) -> float:
	var stock: float = float(station["inventory"].get(item, 0.0))
	if stock <= 0.0 or max_amount <= 0.0:
		return 0.0
	var price := SimEntities.station_sell_price(station, item)
	var free := SimEntities.cargo_free(ship)
	var mass := Commodities.mass_of(item)
	var can_carry := free / mass if mass > 0.0 else 0.0
	var can_afford := float(ship["credits"]) / maxf(price, 0.01)
	var qty := minf(stock, minf(max_amount, minf(can_carry, can_afford)))
	if qty <= 0.0:
		return 0.0
	var cost := qty * price
	station["inventory"][item] = stock - qty
	station["credits"] = float(station["credits"]) + cost
	ship["credits"] = float(ship["credits"]) - cost
	SimEntities.add_cargo(ship, item, qty)
	metrics["transactions"] = int(metrics["transactions"]) + 1
	return qty


static func _can_afford(station: Dictionary, inputs: Dictionary) -> bool:
	for item in inputs:
		if float(station["inventory"].get(item, 0.0)) < float(inputs[item]):
			return false
	return true


static func _consume(station: Dictionary, inputs: Dictionary) -> void:
	for item in inputs:
		station["inventory"][item] = float(station["inventory"].get(item, 0.0)) - float(inputs[item])


static func _produce(station: Dictionary, outputs: Dictionary) -> void:
	for item in outputs:
		station["inventory"][item] = float(station["inventory"].get(item, 0.0)) + float(outputs[item])
