import { Component, type ErrorInfo, type ReactNode } from 'react';

interface Props {
  children: ReactNode;
  fallbackTitle?: string;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

export class ErrorBoundary extends Component<Props, State> {
  public state: State = {
    hasError: false,
    error: null,
    errorInfo: null,
  };

  public static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error, errorInfo: null };
  }

  public componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('Uncaught error in component:', error, errorInfo);
    this.setState({ errorInfo });
  }

  public render() {
    if (this.state.hasError) {
      return (
        <div style={{ padding: 24, color: '#ef4444', background: '#1e293b', borderRadius: 8, margin: 16 }}>
          <h2 style={{ fontSize: 18, fontWeight: 'bold', marginBottom: 8, color: '#f87171' }}>
            {this.props.fallbackTitle ?? 'An error occurred'}
          </h2>
          <pre style={{ whiteSpace: 'pre-wrap', fontSize: 13, color: '#fca5a5' }}>
            {this.state.error?.toString()}
          </pre>
          {this.state.errorInfo && (
            <details style={{ marginTop: 12, color: '#94a3b8', fontSize: 12 }}>
              <summary>Stack Trace</summary>
              <pre style={{ whiteSpace: 'pre-wrap', marginTop: 8 }}>
                {this.state.errorInfo.componentStack}
              </pre>
            </details>
          )}
        </div>
      );
    }

    return this.props.children;
  }
}
