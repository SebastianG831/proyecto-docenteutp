import { Star } from 'lucide-react';

interface RatingStarsProps {
  value: number;
  size?: number;
  interactive?: boolean;
  onChange?: (val: number) => void;
}

export function RatingStars({
  value,
  size = 16,
  interactive = false,
  onChange,
}: RatingStarsProps) {
  const stars = [1, 2, 3, 4, 5];

  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3 }}>
      {stars.map((star) => {
        const filled = star <= Math.round(value);
        if (!interactive) {
          return (
            <Star
              key={star}
              size={size}
              fill={filled ? '#d97706' : 'none'}
              color={filled ? '#d97706' : '#cbd5e1'}
            />
          );
        }
        return (
          <button
            key={star}
            type="button"
            onClick={() => onChange?.(star)}
            aria-label={`${star} estrellas`}
            style={{
              background: 'none',
              border: 'none',
              padding: 2,
              cursor: 'pointer',
              display: 'grid',
              placeItems: 'center',
            }}
          >
            <Star
              size={size}
              fill={star <= value ? '#d97706' : 'none'}
              color={star <= value ? '#d97706' : '#cbd5e1'}
            />
          </button>
        );
      })}
    </span>
  );
}
