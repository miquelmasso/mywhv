String getStateFromPostcode(dynamic postcode) {
  final s = postcode.toString();

  if (s.startsWith('4')) return 'QLD'; // Queensland
  if (s.startsWith('3')) return 'VIC'; // Victoria
  if (s.startsWith('2')) return 'NSW'; // New South Wales
  if (s.startsWith('5')) return 'SA';  // South Australia
  if (s.startsWith('6')) return 'WA';  // Western Australia
  if (s.startsWith('7')) return 'TAS'; // Tasmania
  if (s.startsWith('0')) return 'NT';  // Northern Territory
  return 'UNKNOWN';
}