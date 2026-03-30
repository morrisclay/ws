#!/usr/bin/env bash
# ws-yaml.sh — Ruby-based YAML→JSON parser

ws_yaml_to_json() {
  local file="$1"
  ruby -ryaml -rjson -e "puts JSON.generate(YAML.safe_load(File.read('$file')))" 2>/dev/null
  if [[ $? -ne 0 ]]; then
    ws_die "Failed to parse YAML: $file"
  fi
}

ws_yaml_get() {
  local file="$1" path="$2"
  ruby -ryaml -rjson -e "
    data = YAML.safe_load(File.read('$file'))
    keys = '$path'.split('.')
    result = data
    keys.each do |k|
      break if result.nil?
      result = k =~ /\A\d+\z/ ? result[k.to_i] : result[k]
    end
    if result.is_a?(Hash) || result.is_a?(Array)
      puts JSON.generate(result)
    elsif !result.nil?
      puts result
    end
  " 2>/dev/null
}
