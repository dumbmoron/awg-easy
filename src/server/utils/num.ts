export function rand(min: number, max_inclusive: number) {
  const val = crypto.getRandomValues(new Uint32Array(1))[0] / 2**32;
  return Math.floor(min + (max_inclusive - min + 1) * val);
}

export function checkRange(obj: unknown, name: string, min: number, max: number) {
  const val: unknown = name.split('.').reduce((a, b) => a[b], obj);

  if (typeof val !== 'number')
    throw `${name} is not a number`

  if (val < min)
    throw `${name} is not in range (value=${val} < min=${min})`;

  if (val > max)
    throw `${name} is not in range (value=${val} > max=${max})`;
}
