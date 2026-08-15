import React, { useState, useRef, useEffect } from 'react';
import { ChevronDown, Check } from 'lucide-react';

export interface SelectOption {
  value: string;
  label: string;
}

interface CustomSelectProps {
  options: SelectOption[];
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
}

export const CustomSelect: React.FC<CustomSelectProps> = ({
  options,
  value,
  onChange,
  placeholder,
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  const selectedOption = options.find((opt) => opt.value === value);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  return (
    <div ref={containerRef} style={{ position: 'relative', width: '100%' }}>
      {/* Button Trigger */}
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        style={{
          width: '100%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '12px 16px',
          borderRadius: '10px',
          background: 'var(--glass-bg-mid)',
          border: `1px solid ${isOpen ? 'var(--color-star-gold)' : 'var(--glass-border)'}`,
          boxShadow: isOpen ? '0 0 0 3px rgba(255, 179, 0, 0.18)' : 'none',
          color: selectedOption ? 'var(--text-starlight)' : 'var(--text-dim)',
          fontSize: '16px',
          cursor: 'pointer',
          transition: 'border-color 0.2s ease, box-shadow 0.2s ease',
          outline: 'none',
          textAlign: 'left',
        }}
        aria-haspopup="listbox"
        aria-expanded={isOpen}
      >
        <span>{selectedOption ? selectedOption.label : placeholder || '選択してください'}</span>
        <ChevronDown
          size={18}
          color="var(--text-dim)"
          style={{
            transform: isOpen ? 'rotate(180deg)' : 'rotate(0deg)',
            transition: 'transform 0.2s ease',
            flexShrink: 0,
          }}
        />
      </button>

      {/* Menu Options */}
      {isOpen && (
        <div
          role="listbox"
          style={{
            position: 'absolute',
            top: 'calc(100% + 6px)',
            left: 0,
            width: '100%',
            background: 'rgba(21, 25, 40, 0.98)',
            backdropFilter: 'blur(20px)',
            WebkitBackdropFilter: 'blur(20px)',
            border: '1px solid rgba(255, 255, 255, 0.15)',
            borderRadius: '12px',
            padding: '6px',
            boxShadow: '0 12px 36px rgba(0, 0, 0, 0.6), 0 0 0 1px rgba(255, 179, 0, 0.15)',
            zIndex: 100,
            animation: 'fadeIn 0.16s cubic-bezier(0.16, 1, 0.3, 1) forwards',
          }}
        >
          {options.map((option) => {
            const isSelected = option.value === value;
            return (
              <button
                key={option.value}
                type="button"
                role="option"
                aria-selected={isSelected}
                onClick={() => {
                  onChange(option.value);
                  setIsOpen(false);
                }}
                style={{
                  width: '100%',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  gap: '10px',
                  padding: '10px 14px',
                  borderRadius: '8px',
                  background: isSelected ? 'rgba(255, 179, 0, 0.12)' : 'transparent',
                  color: isSelected ? 'var(--color-star-gold)' : 'var(--text-starlight)',
                  fontSize: '0.95rem',
                  fontWeight: isSelected ? 600 : 400,
                  cursor: 'pointer',
                  border: 'none',
                  textAlign: 'left',
                  transition: 'background 0.15s ease',
                }}
                onMouseEnter={(e) => {
                  if (!isSelected) e.currentTarget.style.background = 'rgba(255, 255, 255, 0.06)';
                }}
                onMouseLeave={(e) => {
                  if (!isSelected) e.currentTarget.style.background = 'transparent';
                }}
              >
                <span>{option.label}</span>
                {isSelected && <Check size={16} color="var(--color-star-gold)" />}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
};
