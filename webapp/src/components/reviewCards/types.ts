import type { LectureTopic, ReviewCard } from '../../types/content';

export interface ReviewTopicGroup {
  topic: LectureTopic;
  cards: ReviewCard[];
  /** このグループの表紙カードが flat リストの何番目か。 */
  startIndex: number;
}

export interface ReviewFlatItem {
  groupIndex: number;
  /** null なら表紙カード。 */
  card: ReviewCard | null;
}
