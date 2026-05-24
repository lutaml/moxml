# frozen_string_literal: true

# Opal runtime patches for moxml specs.
#
# Moxml already handles Opal-specific behavior internally
# (NativeAttachment::Opal, Config::OPAL_DEFAULT_ADAPTER, EntityRegistry::OPAL_ENTITY_DATA).
# This file is loaded only under Opal for any additional test-environment patches.

# Under Opal, moxml uses REXML adapter (Opal reimplements strscan/stringio
# in its stdlib, enabling REXML to compile to JavaScript).
Moxml.configure do |config|
  config.adapter = :rexml
  config.strict_parsing = false
  config.default_encoding = "UTF-8"
  config.entity_load_mode = :optional
end
