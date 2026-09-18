import React, { createContext, useContext, useState, useCallback } from 'react';

interface UploadModalContextValue {
  isOpen: boolean;
  targetCourseId: string | null;
  openUploadModal: (courseId?: string | null) => void;
  closeUploadModal: () => void;
}

const UploadModalContext = createContext<UploadModalContextValue | undefined>(undefined);

export const UploadModalProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [isOpen, setIsOpen] = useState(false);
  const [targetCourseId, setTargetCourseId] = useState<string | null>(null);

  const openUploadModal = useCallback((courseId?: string | null) => {
    setTargetCourseId(courseId ?? null);
    setIsOpen(true);
  }, []);

  const closeUploadModal = useCallback(() => {
    setIsOpen(false);
    setTargetCourseId(null);
  }, []);

  return (
    <UploadModalContext.Provider
      value={{
        isOpen,
        targetCourseId,
        openUploadModal,
        closeUploadModal,
      }}
    >
      {children}
    </UploadModalContext.Provider>
  );
};

export function useUploadModal(): UploadModalContextValue {
  const ctx = useContext(UploadModalContext);
  if (!ctx) {
    throw new Error('useUploadModal must be used within an UploadModalProvider');
  }
  return ctx;
}
