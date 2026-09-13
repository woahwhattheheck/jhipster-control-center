import { Route } from '@/shared/routes/routes.service';
import { SERVER_API_URL } from '@/constants';

export default abstract class AbstractService {
  private GATEWAY_PATH = 'gateway/';

  protected generateUri(route: Route, basePath: string, ...paths: string[]): string {
    const isTerminalManagementPath = paths.length === 0 && basePath.startsWith('/management/') && basePath.endsWith('/');
    const normalizedBasePath = isTerminalManagementPath ? basePath.slice(0, -1) : basePath;
    const controlCenterUri = (SERVER_API_URL !== undefined ? SERVER_API_URL : '') + normalizedBasePath;
    const instanceUri = this.GATEWAY_PATH + route.path + normalizedBasePath;

    return (route?.path?.length > 0 ? instanceUri : controlCenterUri) + paths.join('/');
  }
}
