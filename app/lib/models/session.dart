class Session {
  final String id;
  final String name;
  final String directory;
  final SessionStatus status;
  final String? url;
  final String? error;

  const Session({
    required this.id,
    required this.name,
    required this.directory,
    required this.status,
    this.url,
    this.error,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['session_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      directory: json['directory'] ?? '',
      status: SessionStatus.fromString(json['status'] ?? 'starting'),
      url: json['url'],
      error: json['error'],
    );
  }

  Session copyWith({
    String? id,
    String? name,
    String? directory,
    SessionStatus? status,
    String? url,
    String? error,
  }) {
    return Session(
      id: id ?? this.id,
      name: name ?? this.name,
      directory: directory ?? this.directory,
      status: status ?? this.status,
      url: url ?? this.url,
      error: error ?? this.error,
    );
  }
}

enum SessionStatus {
  starting,
  ready,
  active,
  finished,
  crashed;

  static SessionStatus fromString(String s) {
    return SessionStatus.values.firstWhere(
      (e) => e.name == s,
      orElse: () => SessionStatus.starting,
    );
  }

  String get label {
    return switch (this) {
      starting => 'Starting',
      ready => 'Ready',
      active => 'Active',
      finished => 'Finished',
      crashed => 'Crashed',
    };
  }
}
