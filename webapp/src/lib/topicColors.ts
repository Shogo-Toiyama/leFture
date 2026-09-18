/**
 * topic_color_utils.dart と同じ配色。
 * トピックを赤(0°)〜紫(280°)に均等割りし、彩度70% / 明度48%で返す。
 */
export function topicColor(index: number, totalTopics: number): string {
  if (totalTopics <= 0) return 'hsl(0 57% 67%)';
  const hue = totalTopics === 1 ? 0 : Math.min(Math.max(index / (totalTopics - 1), 0), 1) * 280;
  return `hsl(${hue.toFixed(1)} 70% 48%)`;
}
