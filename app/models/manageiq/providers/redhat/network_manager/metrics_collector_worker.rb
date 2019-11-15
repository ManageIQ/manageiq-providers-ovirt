class ManageIQ::Providers::Redhat::NetworkManager::MetricsCollectorWorker < ::MiqEmsMetricsCollectorWorker
  require_nested :Runner

  self.default_queue_name = "redhat_network"

  def friendly_name
    @friendly_name ||= "C&U Metrics Collector for Redhat Network"
  end

  def self.settings_name
    :ems_metrics_collector_worker_redhat_network
  end
end
