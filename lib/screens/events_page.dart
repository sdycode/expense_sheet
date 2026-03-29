import 'package:MoneyTracker/models/event.dart';
import 'package:MoneyTracker/services/services_module.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EventsPage extends StatefulWidget {
  final String spreadsheetId;

  const EventsPage({super.key, required this.spreadsheetId});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  final FirebaseDatabaseService _db = FirebaseDatabaseService();
  List<Event> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      final events = await _db.getEvents(widget.spreadsheetId);
      setState(() {
        _events = events;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading events: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showAddEditDialog([Event? existing]) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final notesController = TextEditingController(text: existing?.notes ?? '');
    DateTime? date = existing?.date;
    DateTime? startDate = existing?.startDate;
    DateTime? endDate = existing?.endDate;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(existing == null ? 'Add Event' : 'Edit Event'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name *',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (Optional)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(8),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: Text(
                      date != null
                          ? DateFormat('d MMM yyyy').format(date!)
                          : 'Date (Optional)',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final p = await showDatePicker(
                        context: context,
                        initialDate: date ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (p != null) setDialogState(() => date = p);
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    title: Text(
                      startDate != null
                          ? 'Start: ${DateFormat('d MMM yyyy').format(startDate!)}'
                          : 'Start Date (Optional)',
                    ),
                    trailing: const Icon(Icons.date_range),
                    onTap: () async {
                      final p = await showDatePicker(
                        context: context,
                        initialDate: startDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (p != null) setDialogState(() => startDate = p);
                    },
                  ),
                  ListTile(
                    title: Text(
                      endDate != null
                          ? 'End: ${DateFormat('d MMM yyyy').format(endDate!)}'
                          : 'End Date (Optional)',
                    ),
                    trailing: const Icon(Icons.date_range),
                    onTap: () async {
                      final p = await showDatePicker(
                        context: context,
                        initialDate: endDate ?? startDate ?? DateTime.now(),
                        firstDate: startDate ?? DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (p != null) setDialogState(() => endDate = p);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter event name')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  final event = Event(
                    id: existing?.id ?? '',
                    name: name,
                    notes: notesController.text.trim().isEmpty
                        ? null
                        : notesController.text.trim(),
                    date: date,
                    startDate: startDate,
                    endDate: endDate,
                  );
                  if (existing != null) {
                    final ok = await _db.updateEvent(
                      widget.spreadsheetId,
                      event,
                    );
                    if (ok && mounted) {
                      setState(() {
                        final i = _events.indexWhere(
                          (e) => e.id == existing.id,
                        );
                        if (i >= 0) _events[i] = event;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Event updated'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } else {
                    final id = await _db.addEvent(widget.spreadsheetId, event);
                    if (id != null && mounted) {
                      setState(() => _events.add(event.copyWith(id: id)));
                      try {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Event added'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {}
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteEvent(Event event) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text('Delete event "${event.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await _db.deleteEvent(widget.spreadsheetId, event.id);
    if (ok && mounted) {
      setState(() => _events.removeWhere((e) => e.id == event.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event deleted'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No events yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create events to group expenses',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadEvents,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _events.length,
                itemBuilder: (context, index) {
                  final event = _events[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        event.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (event.notes != null && event.notes!.isNotEmpty)
                            Text(
                              event.notes!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (event.date != null ||
                              event.startDate != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              event.date != null
                                  ? DateFormat('d MMM yyyy').format(event.date!)
                                  : (event.startDate != null &&
                                        event.endDate != null)
                                  ? '${DateFormat('d MMM').format(event.startDate!)} - ${DateFormat('d MMM yyyy').format(event.endDate!)}'
                                  : event.startDate != null
                                  ? 'From ${DateFormat('d MMM yyyy').format(event.startDate!)}'
                                  : '',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _showAddEditDialog(event),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete,
                              size: 20,
                              color: Colors.red[700],
                            ),
                            onPressed: () => _deleteEvent(event),
                          ),
                        ],
                      ),
                      onTap: () => _showAddEditDialog(event),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
