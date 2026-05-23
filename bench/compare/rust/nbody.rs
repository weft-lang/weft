#[derive(Clone, Copy)]
struct Body {
    x: f64,
    y: f64,
    z: f64,
    vx: f64,
    vy: f64,
    vz: f64,
    mass: f64,
}

fn energy(bodies: &[Body]) -> f64 {
    let mut total = 0.0;
    for i in 0..bodies.len() {
        let b = bodies[i];
        total += 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz);
        for c in bodies.iter().skip(i + 1) {
            let dx = b.x - c.x;
            let dy = b.y - c.y;
            let dz = b.z - c.z;
            total -= b.mass * c.mass / (dx * dx + dy * dy + dz * dz).sqrt();
        }
    }
    total
}

fn nbody_final_energy(steps: i64) -> f64 {
    let days_per_year = 365.24;
    let solar_mass = 39.47841760435743;
    let dt = 0.01;
    let mut bodies = [
        Body { x: 0.0, y: 0.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0, mass: solar_mass },
        Body { x: 4.84143144246472090, y: -1.16032004402742839, z: -0.103622044471123109, vx: 0.00166007664274403694 * days_per_year, vy: 0.00769901118419740425 * days_per_year, vz: -0.0000690460016972063023 * days_per_year, mass: 0.000954791938424326609 * solar_mass },
        Body { x: 8.34336671824457987, y: 4.12479856412430479, z: -0.403523417114321381, vx: -0.00276742510726862411 * days_per_year, vy: 0.00499852801234917238 * days_per_year, vz: 0.0000230417297573763929 * days_per_year, mass: 0.000285885980666130812 * solar_mass },
        Body { x: 12.8943695621391310, y: -15.1111514016986312, z: -0.223307578892655734, vx: 0.00296460137564761618 * days_per_year, vy: 0.00237847173959480950 * days_per_year, vz: -0.0000296589568540237556 * days_per_year, mass: 0.0000436624404335156298 * solar_mass },
        Body { x: 15.3796971148509165, y: -25.9193146099879641, z: 0.179258772950371181, vx: 0.00268067772490389322 * days_per_year, vy: 0.00162824170038242295 * days_per_year, vz: -0.0000951592254519715870 * days_per_year, mass: 0.0000515138902046611451 * solar_mass },
    ];

    let mut px = 0.0;
    let mut py = 0.0;
    let mut pz = 0.0;
    for b in bodies.iter() {
        px += b.vx * b.mass;
        py += b.vy * b.mass;
        pz += b.vz * b.mass;
    }
    bodies[0].vx = -px / solar_mass;
    bodies[0].vy = -py / solar_mass;
    bodies[0].vz = -pz / solar_mass;

    for _ in 0..steps {
        for i in 0..bodies.len() {
            for j in i + 1..bodies.len() {
                let dx = bodies[i].x - bodies[j].x;
                let dy = bodies[i].y - bodies[j].y;
                let dz = bodies[i].z - bodies[j].z;
                let d2 = dx * dx + dy * dy + dz * dz;
                let mag = dt / (d2 * d2.sqrt());
                bodies[i].vx -= dx * bodies[j].mass * mag;
                bodies[i].vy -= dy * bodies[j].mass * mag;
                bodies[i].vz -= dz * bodies[j].mass * mag;
                bodies[j].vx += dx * bodies[i].mass * mag;
                bodies[j].vy += dy * bodies[i].mass * mag;
                bodies[j].vz += dz * bodies[i].mass * mag;
            }
        }
        for b in bodies.iter_mut() {
            b.x += dt * b.vx;
            b.y += dt * b.vy;
            b.z += dt * b.vz;
        }
    }

    energy(&bodies)
}

fn main() {
    let expected = -0.16907807060863048;
    let got = nbody_final_energy(50000);
    if (got - expected).abs() >= 0.000000001 {
        panic!("{}", got);
    }
}
