/// A guide ends only on a successful, visible reply from its own send request.
bool isOnboardingReply(Map<String, dynamic> result) {
  if (result['success'] != true || result['silent'] == true) return false;
  return (result['messages'] as List? ?? const []).whereType<Map>().any(
    (message) =>
        message['role'] == 'assistant' &&
        message['type'] != 'inner_thought' &&
        ((message['content']?.toString().trim().isNotEmpty ?? false) ||
            (message['file_path']?.toString().trim().isNotEmpty ?? false)),
  );
}
