import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CyberRakshaApp());
}

class CyberRakshaApp extends StatelessWidget {
  const CyberRakshaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CyberRaksha',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 2,
        ),
      ),
      home: const OnboardingApp(),
    );
  }
}

class OnboardingApp extends StatefulWidget {
  const OnboardingApp({super.key});

  @override
  State<OnboardingApp> createState() => _OnboardingAppState();
}

class _OnboardingAppState extends State<OnboardingApp> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Form Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _complaintController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  // Dropdown Categories
  String _selectedCategory = 'Financial Fraud / UPI Scam';
  final List<String> _categories = [
    'Financial Fraud / UPI Scam',
    'Phishing / Fraudulent Web Link',
    'Deepfake / Image Morphing',
    'Identity Theft / Account Hacking',
    'Cyberstalking / Harassment',
    'Other Cyber Crime'
  ];

  // Speech Recognition
  late stt.SpeechToText _speech;
  bool _isListening = false;

  // File Picker
  List<PlatformFile> _attachedFiles = [];

  // Local Storage Status
  String _storageStatusMessage = '';

  // URL Scanner Results
  String _urlAnalysisResult = '';
  Color _urlResultColor = Colors.black87;

  // Final Generated Complaint
  String _generatedComplaint = '';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _loadSavedData();
  }

  // --- LOCAL STORAGE LOGIC ---
  Future<void> _saveDataLocally() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('complainant_name', _nameController.text);
    await prefs.setString('incident_category', _selectedCategory);
    await prefs.setString('complaint_text', _complaintController.text);

    if (mounted) {
      setState(() {
        _storageStatusMessage =
            "Draft saved locally at ${DateFormat('HH:mm:ss').format(DateTime.now())} ✅";
      });
    }
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nameController.text = prefs.getString('complainant_name') ?? '';
        _selectedCategory =
            prefs.getString('incident_category') ?? _categories[0];
        _complaintController.text = prefs.getString('complaint_text') ?? '';
      });
    }
  }

  // --- WEB-SAFE SPEECH TO TEXT LOGIC ---
  void _listenVoice() async {
    try {
      if (!_isListening) {
        bool available = await _speech.initialize(
          onStatus: (val) {
            if (val == 'done' || val == 'notListening') {
              if (mounted) setState(() => _isListening = false);
            }
          },
          onError: (val) {
            if (mounted) setState(() => _isListening = false);
          },
        );
        if (available) {
          if (mounted) setState(() => _isListening = true);
          _speech.listen(
            onResult: (val) {
              if (mounted) {
                setState(() {
                  _complaintController.text = val.recognizedWords;
                });
              }
            },
          );
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      "Microphone access unavailable on this browser preview.")),
            );
          }
        }
      } else {
        if (mounted) setState(() => _isListening = false);
        _speech.stop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Speech recognition error: $e")),
        );
      }
    }
  }

  // --- FILE PICKER LOGIC ---
  Future<void> _pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'png', 'pdf'],
      );

      if (result != null && mounted) {
        setState(() {
          _attachedFiles = result.files;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("File picker error: $e")),
        );
      }
    }
  }

  // --- COMPLAINT GENERATION ---
  void _generateDraft() {
    String date = DateFormat('dd-MM-yyyy').format(DateTime.now());
    String filesSummary = _attachedFiles.isEmpty
        ? 'No external files attached.'
        : '${_attachedFiles.length} file(s) attached: ' +
            _attachedFiles.map((f) => f.name).join(', ');

    setState(() {
      _generatedComplaint = """TO,
The Cyber Crime Cell, Government Cyber Authority
Date: $date

SUBJECT: Formal Complaint Regarding $_selectedCategory

Respected Officer,

I am submitting a formal report regarding a cyber crime incident involving "$_selectedCategory".

1. COMPLAINANT DETAILS:
   - Name: ${_nameController.text.isEmpty ? 'Anonymous / Citizen' : _nameController.text}

2. INCIDENT CATEGORY:
   - Incident Type: $_selectedCategory

3. INCIDENT STATEMENT & DETAILS:
   ${_complaintController.text.isEmpty ? 'Detailed statement pending.' : _complaintController.text}

4. EVIDENCE PRESERVED:
   - $filesSummary

I request the Cyber Crime Investigation Cell to take formal note of this incident, initiate necessary action under applicable laws, and trace the perpetrator.

Sincerely,
${_nameController.text.isEmpty ? 'Citizen' : _nameController.text}""";
    });
  }

  // --- PDF GENERATION & PRINTING ---
  Future<void> _downloadPDF() async {
    if (_generatedComplaint.isEmpty) _generateDraft();

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Text(
              _generatedComplaint,
              style: const pw.TextStyle(fontSize: 12, height: 1.5),
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  // --- HEURISTIC URL SCANNER ---
  void _analyzeURL(String inputUrl) {
    if (inputUrl.trim().isEmpty) {
      setState(() {
        _urlAnalysisResult = "Please enter a valid URL to check.";
        _urlResultColor = Colors.orange.shade800;
      });
      return;
    }

    String lower = inputUrl.toLowerCase().trim();
    List<String> warnings = [];

    if (!lower.startsWith("https://")) {
      warnings.add("⚠️ Unencrypted Connection (Not HTTPS).");
    }
    if (RegExp(r'(\d{1,3}\.){3}\d{1,3}').hasMatch(lower)) {
      warnings.add("🚨 IP Address URL (High Risk Phishing Pattern).");
    }
    if (lower.contains("login") ||
        lower.contains("verify") ||
        lower.contains("bank") ||
        lower.contains("kyc") ||
        lower.contains("update")) {
      warnings.add("⚠️ Suspicious credential harvesting keywords detected.");
    }

    setState(() {
      if (warnings.isEmpty) {
        _urlAnalysisResult =
            "✅ Standard URL Structure detected. Always verify domain before logging in.";
        _urlResultColor = Colors.green.shade800;
      } else {
        _urlAnalysisResult = warnings.join("\n");
        _urlResultColor = Colors.red.shade800;
      }
    });
  }

  // --- TELEPHONY DIALER ---
  Future<void> _makeCall(String number) async {
    final Uri url = Uri.parse('tel:$number');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not launch dialer for $number")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CyberRaksha Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save Draft',
            onPressed: () {
              _saveDataLocally();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Draft Progress Saved Locally!")),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Slide Indicators
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    height: 8.0,
                    width: _currentPage == index ? 24.0 : 8.0,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? const Color(0xFF1E3A8A)
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                  );
                }),
              ),
            ),

            // Page View Slider
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (int page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                children: [
                  _buildSlide1Category(),
                  _buildSlide2Statement(),
                  _buildSlide3Evidence(),
                  _buildSlide4DraftPDF(),
                  _buildSlide5UrlAndChecklist(),
                ],
              ),
            ),

            // Navigation Controls
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentPage > 0)
                    OutlinedButton(
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: const Text('Previous'),
                    )
                  else
                    const SizedBox.shrink(),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      if (_currentPage < 4) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        _saveDataLocally();
                      }
                    },
                    child: Text(_currentPage == 4 ? 'Finish' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- SLIDE 1 ---
  Widget _buildSlide1Category() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 1: Incident Category',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Select the type of cyber crime experienced and enter your name (optional).',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Complainant Full Name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Select Cyber Incident Type',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.report_problem),
            ),
            items: _categories.map((String category) {
              return DropdownMenuItem<String>(
                value: category,
                child: Text(
                  category,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedCategory = newValue;
                });
              }
            },
          ),
          const SizedBox(height: 30),
          const Text(
            'Immediate Emergency Helplines:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.phone),
                  label: const Text('1930 Cyber Fraud'),
                  onPressed: () => _makeCall('1930'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.local_police),
                  label: const Text('112 Emergency'),
                  onPressed: () => _makeCall('112'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- SLIDE 2 ---
  Widget _buildSlide2Statement() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 2: Incident Narrative',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Describe the sequence of events clearly. You can use typed text or the speech microphone.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _complaintController,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText:
                  'Describe what happened (e.g. Transaction IDs, fraudulent phone numbers, social media handles)...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isListening ? Colors.red : const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
              label:
                  Text(_isListening ? 'Stop Listening' : 'Hold / Tap to Speak'),
              onPressed: _listenVoice,
            ),
          ),
        ],
      ),
    );
  }

  // --- SLIDE 3 ---
  Widget _buildSlide3Evidence() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 3: Evidence Locker',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Attach screenshots, chat transaction exports, or altered image files from local storage.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            icon: const Icon(Icons.attach_file),
            label: const Text('Pick Evidence Screenshots / Files'),
            onPressed: _pickFiles,
          ),
          const SizedBox(height: 20),
          _attachedFiles.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No evidence files selected yet.'),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _attachedFiles.length,
                  itemBuilder: (context, index) {
                    final file = _attachedFiles[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.insert_drive_file,
                            color: Color(0xFF1E3A8A)),
                        title: Text(file.name),
                        subtitle:
                            Text('${(file.size / 1024).toStringAsFixed(1)} KB'),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  // --- SLIDE 4 ---
  Widget _buildSlide4DraftPDF() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 4: Draft Legal Complaint',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(45),
            ),
            icon: const Icon(Icons.description),
            label: const Text('Generate Formal Complaint'),
            onPressed: _generateDraft,
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade400),
            ),
            child: Text(
              _generatedComplaint.isEmpty
                  ? 'Click "Generate Formal Complaint" above to review document.'
                  : _generatedComplaint,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Download PDF'),
                  onPressed: _downloadPDF,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('Share Text'),
                  onPressed: () {
                    if (_generatedComplaint.isNotEmpty) {
                      Share.share(_generatedComplaint);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- SLIDE 5 ---
  Widget _buildSlide5UrlAndChecklist() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 5: Link Analyzer & Emergency Checklist',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Paste Suspicious Link / URL',
              hintText: 'http://192.168.0.1/verify-bank',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _analyzeURL(_urlController.text),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_urlAnalysisResult.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _urlResultColor.withOpacity(0.1),
                border: Border.all(color: _urlResultColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _urlAnalysisResult,
                style: TextStyle(
                    color: _urlResultColor, fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            'Golden Hour Emergency Checklist:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12.0),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.check_box, color: Colors.green),
                    title: Text('1. Call 1930 to freeze bank debit pipelines.'),
                  ),
                  ListTile(
                    leading: Icon(Icons.check_box, color: Colors.green),
                    title: Text(
                        '2. Take full-screen screenshots of payment reference IDs.'),
                  ),
                  ListTile(
                    leading: Icon(Icons.check_box, color: Colors.green),
                    title:
                        Text('3. Report and block the scammer phone/profile.'),
                  ),
                ],
              ),
            ),
          ),
          if (_storageStatusMessage.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              _storageStatusMessage,
              style: const TextStyle(
                  color: Colors.green, fontWeight: FontWeight.bold),
            ),
          ]
        ],
      ),
    );
  }
}
