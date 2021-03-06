# frozen_string_literal: true

module Pharos
  module Phases
    class SetupMaster < Pharos::Phase
      title "Setup master configuration files"

      def kubeadm
        Pharos::Kubeadm::ConfigGenerator.new(@config, @host)
      end

      def call
        push_external_etcd_certs if @config.etcd&.certificate
        push_audit_policy if @config.audit
        push_audit_config if @config.audit&.webhook&.server
        push_authentication_token_webhook_config if @config.authentication&.token_webhook
        push_oidc_certs if @config.authentication&.oidc&.ca_file

        return unless @config.cloud&.intree_provider? && @config.cloud&.config

        push_intree_cloud_config
      end

      # TODO: lock down permissions on key
      def push_external_etcd_certs
        logger.info { "Pushing external etcd certificates ..." }

        transport.exec!('sudo mkdir -p /etc/pharos/etcd')
        transport.file('/etc/pharos/etcd/ca-certificate.pem').write(File.open(@config.etcd.ca_certificate))
        transport.file('/etc/pharos/etcd/certificate.pem').write(File.open(@config.etcd.certificate))
        transport.file('/etc/pharos/etcd/certificate-key.pem').write(File.open(@config.etcd.key))
      end

      def push_audit_policy
        transport.exec!("sudo mkdir -p /etc/pharos/audit")
        transport.file("/etc/pharos/audit/policy.yml").write(parse_resource_file('audit/policy.yml'))
      end

      def push_audit_config
        logger.info { "Pushing audit configs to master ..." }
        transport.exec!("sudo mkdir -p /etc/pharos/audit")
        transport.file("/etc/pharos/audit/webhook.yml").write(
          parse_resource_file('audit/webhook-config.yml.erb', server: @config.audit.server)
        )
      end

      # @param webhook_config [Hash]
      def push_authentication_token_webhook_certs(webhook_config)
        logger.info { "Pushing token authentication webhook certificates ..." }

        transport.exec!("sudo mkdir -p /etc/pharos/token_webhook")
        transport.file('/etc/pharos/token_webhook/ca.pem').write(File.open(File.expand_path(webhook_config[:cluster][:certificate_authority]))) if webhook_config[:cluster][:certificate_authority]
        transport.file('/etc/pharos/token_webhook/cert.pem').write(File.open(File.expand_path(webhook_config[:user][:client_certificate]))) if webhook_config[:user][:client_certificate]
        transport.file('/etc/pharos/token_webhook/key.pem').write(File.open(File.expand_path(webhook_config[:user][:client_key]))) if webhook_config[:user][:client_key]
      end

      def push_authentication_token_webhook_config
        webhook_config = @config.authentication.token_webhook.config

        logger.info { "Pushing token authentication webhook config ..." }
        auth_token_webhook_config = kubeadm.generate_authentication_token_webhook_config(webhook_config)

        transport.exec!('sudo mkdir -p /etc/kubernetes/authentication')
        transport.file('/etc/kubernetes/authentication/token-webhook-config.yaml').write(auth_token_webhook_config.to_yaml)

        push_authentication_token_webhook_certs(webhook_config)
      end

      def push_intree_cloud_config
        logger.info { "Pushing cloud-config to master ..." }
        transport.exec!('sudo mkdir -p /etc/pharos/cloud')
        transport.file('/etc/pharos/cloud/cloud-config').write(File.open(File.expand_path(@config.cloud.config)))
      end

      def push_oidc_certs
        logger.info { "Pushing OIDC certificates to master ..." }
        transport.exec!('sudo mkdir -p /etc/kubernetes/authentication')
        transport.file('/etc/kubernetes/authentication/oidc_ca.crt').write(File.open(File.expand_path(@config.authentication.oidc.ca_file)))
      end
    end
  end
end
