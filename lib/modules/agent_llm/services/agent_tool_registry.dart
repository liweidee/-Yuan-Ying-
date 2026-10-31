// lib/modules/agent_llm/services/agent_tool_registry.dart

class AgentTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final Future<dynamic> Function(Map<String, dynamic> args) execute;

  const AgentTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });
}

class AgentToolRegistry {
  AgentToolRegistry._();
  static final AgentToolRegistry instance = AgentToolRegistry._();

  final Map<String, AgentTool> _tools = {};

  void register(AgentTool tool) => _tools[tool.name] = tool;

  void clear() => _tools.clear();

  bool get isEmpty => _tools.isEmpty;

  List<Map<String, dynamic>> get toolDefinitions => _tools.values
      .map((t) => {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': t.parameters,
            },
          })
      .toList();

  AgentTool? find(String name) => _tools[name];
}