import '../models/service_item.dart';

abstract interface class ServiceCatalogDataSource {
  Stream<List<ServiceItem>> getServicesStream();
}

abstract interface class DatabaseServiceInterface
    implements ServiceCatalogDataSource {}
