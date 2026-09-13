import AbstractService from '@/applications/abstract.service';
import { SERVER_API_URL } from '@/constants';

class TestService extends AbstractService {
  public uri(route: any, basePath: string, ...paths: string[]): string {
    return this.generateUri(route, basePath, ...paths);
  }
}

describe('Abstract Service', () => {
  let service: TestService;

  beforeEach(() => {
    service = new TestService();
  });

  it('should remove a trailing slash from terminal control-center management endpoints', () => {
    const serverApiUrl = SERVER_API_URL !== undefined ? SERVER_API_URL : '';

    expect(service.uri({ path: '' }, '/management/health/')).toBe(`${serverApiUrl}/management/health`);
  });

  it('should remove a trailing slash from terminal gateway management endpoints', () => {
    expect(service.uri({ path: 'orders/instance-1' }, '/management/health/')).toBe('gateway/orders/instance-1/management/health');
  });

  it('should preserve the separator when appending a child path', () => {
    expect(service.uri({ path: 'orders/instance-1' }, '/management/loggers/', 'ROOT')).toBe(
      'gateway/orders/instance-1/management/loggers/ROOT'
    );
  });

  it('should preserve unrelated terminal trailing slashes', () => {
    expect(service.uri({ path: 'orders/instance-1' }, '/api/custom/')).toBe('gateway/orders/instance-1/api/custom/');
  });
});
