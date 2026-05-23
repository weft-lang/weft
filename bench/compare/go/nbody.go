package main

import "math"

type body struct {
	x, y, z    float64
	vx, vy, vz float64
	mass       float64
}

func energy(bodies []body) float64 {
	total := 0.0
	for i := range bodies {
		b := &bodies[i]
		total += 0.5 * b.mass * (b.vx*b.vx + b.vy*b.vy + b.vz*b.vz)
		for j := i + 1; j < len(bodies); j++ {
			c := &bodies[j]
			dx := b.x - c.x
			dy := b.y - c.y
			dz := b.z - c.z
			total -= b.mass * c.mass / math.Sqrt(dx*dx+dy*dy+dz*dz)
		}
	}
	return total
}

func nbodyFinalEnergy(steps int) float64 {
	daysPerYear := 365.24
	solarMass := 39.47841760435743
	dt := 0.01
	bodies := []body{
		{mass: solarMass},
		{4.841431442465, -1.160320044027, -0.103622044471, 0.001660076643 * daysPerYear, 0.007699011184 * daysPerYear, -0.000069046002 * daysPerYear, 0.000954791938 * solarMass},
		{8.343366718245, 4.124798564124, -0.403523417114, -0.002767425107 * daysPerYear, 0.004998528012 * daysPerYear, 0.000023041730 * daysPerYear, 0.000285885981 * solarMass},
		{12.894369562139, -15.111151401699, -0.223307578893, 0.002964601376 * daysPerYear, 0.002378471740 * daysPerYear, -0.000029658957 * daysPerYear, 0.000043662440 * solarMass},
		{15.379697114851, -25.919314609988, 0.179258772950, 0.002680677725 * daysPerYear, 0.001628241700 * daysPerYear, -0.000095159225 * daysPerYear, 0.000051513890 * solarMass},
	}

	px := 0.0
	py := 0.0
	pz := 0.0
	for i := range bodies {
		px += bodies[i].vx * bodies[i].mass
		py += bodies[i].vy * bodies[i].mass
		pz += bodies[i].vz * bodies[i].mass
	}
	bodies[0].vx = -px / solarMass
	bodies[0].vy = -py / solarMass
	bodies[0].vz = -pz / solarMass

	for step := 0; step < steps; step++ {
		for i := 0; i < len(bodies); i++ {
			for j := i + 1; j < len(bodies); j++ {
				dx := bodies[i].x - bodies[j].x
				dy := bodies[i].y - bodies[j].y
				dz := bodies[i].z - bodies[j].z
				d2 := dx*dx + dy*dy + dz*dz
				mag := dt / (d2 * math.Sqrt(d2))
				bodies[i].vx -= dx * bodies[j].mass * mag
				bodies[i].vy -= dy * bodies[j].mass * mag
				bodies[i].vz -= dz * bodies[j].mass * mag
				bodies[j].vx += dx * bodies[i].mass * mag
				bodies[j].vy += dy * bodies[i].mass * mag
				bodies[j].vz += dz * bodies[i].mass * mag
			}
		}
		for i := range bodies {
			bodies[i].x += dt * bodies[i].vx
			bodies[i].y += dt * bodies[i].vy
			bodies[i].z += dt * bodies[i].vz
		}
	}

	return energy(bodies)
}

func main() {
	expected := -0.16907807060863048
	got := nbodyFinalEnergy(50000)
	if math.Abs(got-expected) >= 0.000000001 {
		panic(got)
	}
}
