double calculatePercentage(int attended, int total) {
  if (total == 0) return 0.0;
  return (attended / total) * 100;
}
