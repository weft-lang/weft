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
		{4.84143144246472090, -1.16032004402742839, -0.103622044471123109, 0.00166007664274403694 * daysPerYear, 0.00769901118419740425 * daysPerYear, -0.0000690460016972063023 * daysPerYear, 0.000954791938424326609 * solarMass},
		{8.34336671824457987, 4.12479856412430479, -0.403523417114321381, -0.00276742510726862411 * daysPerYear, 0.00499852801234917238 * daysPerYear, 0.0000230417297573763929 * daysPerYear, 0.000285885980666130812 * solarMass},
		{12.8943695621391310, -15.1111514016986312, -0.223307578892655734, 0.00296460137564761618 * daysPerYear, 0.00237847173959480950 * daysPerYear, -0.0000296589568540237556 * daysPerYear, 0.0000436624404335156298 * solarMass},
		{15.3796971148509165, -25.9193146099879641, 0.179258772950371181, 0.00268067772490389322 * daysPerYear, 0.00162824170038242295 * daysPerYear, -0.0000951592254519715870 * daysPerYear, 0.0000515138902046611451 * solarMass},
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
