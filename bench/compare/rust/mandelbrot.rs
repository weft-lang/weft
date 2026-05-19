fn mandelbrot_count(size: i64, max_iter: i64) -> i64 {
    let inv_size = 1.0 / size as f64;
    let mut total = 0_i64;
    for y in 0..size {
        let ci = y as f64 * 2.0 * inv_size - 1.0;
        for x in 0..size {
            let cr = x as f64 * 3.0 * inv_size - 2.0;
            let mut zr = 0.0;
            let mut zi = 0.0;
            let mut mag2 = 0.0;
            let mut iter = 0_i64;
            while iter < max_iter && mag2 <= 4.0 {
                let zr2 = zr * zr;
                let zi2 = zi * zi;
                let next_zi = 2.0 * zr * zi;
                let next_zr = zr2 - zi2;
                zi = next_zi + ci;
                zr = next_zr + cr;
                let mag_zr = zr * zr;
                let mag_zi = zi * zi;
                mag2 = mag_zr + mag_zi;
                iter += 1;
            }
            if iter == max_iter {
                total += 1;
            }
        }
    }
    total
}

fn main() {
    let size = 256_i64;
    let max_iter = 80_i64;
    let runs = 3;
    let mut total = 0_i64;
    for _ in 0..runs {
        total += mandelbrot_count(size, max_iter);
    }
    if total != 51201 {
        panic!("{}", total);
    }
}
