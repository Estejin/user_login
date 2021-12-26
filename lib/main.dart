import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:user_login/src/authentication.dart';
import 'firebase_options.dart';
import 'src/widgets.dart';
void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => ApplicationState(),
      builder: (context, _) => App(),
    ),
  );
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Meetup',
      theme: ThemeData(
        buttonTheme: Theme.of(context).buttonTheme.copyWith(
          highlightColor: Colors.deepPurple,
        ),
        primarySwatch: Colors.deepPurple,
        textTheme: GoogleFonts.robotoTextTheme(
          Theme.of(context).textTheme,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Meetup'),
      ),
      body: ListView(
        children: <Widget>[
          Image.asset('assets/codelab.png'),
          const SizedBox(height: 8),
          const IconAndDetail(Icons.calendar_today, 'October 30'),
          const IconAndDetail(Icons.location_city, 'San Francisco'),
          Consumer<ApplicationState>(
              builder: (context, appState, _) => Authentication(
                  loginState: appState.loginState,
                  email: appState.email,
                  startLoginFlow: appState.startLoginFlow,
                  verifyEmail: appState.verifyEmail,
                  signInWithEmailAndPassword: appState.signInWithEmailAndPassword,
                  cancelRegistration: appState.cancelRegistration,
                  registerAccount: appState.registerAccount,
                  signOut: appState.signOut)
          ),
          const Divider(
            height: 8,
            thickness: 1,
            indent: 8,
            endIndent: 8,
            color: Colors.grey,
          ),
          const Header("What we'll be doing"),
          const Paragraph(
            'Join us for a day full of Firebase Workshops and Pizza!',
          ),
          Consumer<ApplicationState>(
            builder: (context, appState, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (appState.attendees >= 2)
                  Paragraph('${appState.attendees} people going')
                else if (appState.attendees == 1)
                  Paragraph('1 person going')
                else
                  const Paragraph('No one going'),
                if (appState.loginState == ApplicationLoginState.loggedIn) ...[
                  YesNoSelection(
                      state: appState.attending,
                      onSelection: (attending) => appState.attending = attending),
                  const Header('Discussion'),
                  GuestBook(
                    addMessage:(message) => appState.addMessageToGuestBook(message),
                    messages: appState.guestBookMessage,
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }
}
//
class ApplicationState extends ChangeNotifier {
  ApplicationLoginState _loginState = ApplicationLoginState.loggedOut;
  ApplicationLoginState get loginState => _loginState;
  //
  String? _email;
  String? get email => _email;
  //
  StreamSubscription<QuerySnapshot> ? _guestBookSubscription;
  List<GuestBookMessage> _guestBookMessages = [];
  List<GuestBookMessage> get guestBookMessage => _guestBookMessages;
  //
  int _attendees = 0;
  int get attendees => _attendees;
  //
  Attending _attending = Attending.unknown;
  StreamSubscription<DocumentSnapshot> ? _attendingSubscription;
  //
  Attending get attending => _attending;
  set attending(Attending attending) {
    final userDoc = FirebaseFirestore.instance
        .collection('attendees')
        .doc(FirebaseAuth.instance.currentUser!.uid);
    if (attending == Attending.yes) {
      userDoc.set(<String, dynamic>{'attending' : true});
    } else {
      userDoc.set(<String, dynamic>{'attending' : false});
    }
  }
  //
  ApplicationState() {
    init();
  }
  Future<void> init() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    //
    FirebaseFirestore.instance
      .collection('attendees')
      .where('attending', isEqualTo: true)
      .snapshots()
      .listen((snapshot) {
        _attendees = snapshot.docs.length;
        notifyListeners();
      });
    //
    FirebaseAuth.instance.userChanges().listen((user) {
      if (user != null) {
        _loginState = ApplicationLoginState.loggedIn;
        _guestBookSubscription = FirebaseFirestore.instance
          .collection('guestbook')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .listen((snapshot) {
              _guestBookMessages = [];
              for(final document in snapshot.docs) {
                _guestBookMessages.add(
                  GuestBookMessage(
                      document.data()['name'] as String,
                      document.data()['text'] as String
                  ),
                );
              }
              notifyListeners();
        });
        //attendees
        _attendingSubscription = FirebaseFirestore.instance
          .collection('attendees')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
          if (snapshot.data() != null) {
            if (snapshot.data()!['attending'] as bool) {
              _attending = Attending.yes;
            } else {
              _attending = Attending.no;
            }
          } else {
            _attending = Attending.unknown;
          }
          notifyListeners();
        });
      } else {
        _loginState = ApplicationLoginState.loggedOut;
        _guestBookMessages = [];
        _guestBookSubscription?.cancel();
        _attendingSubscription?.cancel();
      }
      notifyListeners();
    });
  }
  void startLoginFlow() {
    _loginState = ApplicationLoginState.emailAddress;
    notifyListeners();
  }
  Future<void> verifyEmail(
      String email,
      void Function(FirebaseAuthException e) errorCallback,
      )  async {
    try {
      var methods =
      await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
      if (methods.contains('password')) {
        _loginState = ApplicationLoginState.password;
      } else {
        _loginState = ApplicationLoginState.register;
      }
      _email = email;
      notifyListeners();
    } on FirebaseAuthException catch (e) {
      errorCallback(e);
    }
  }
  Future<void> signInWithEmailAndPassword (
      String email,
      String password,
      void Function(FirebaseAuthException e) errorCallback) async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch(e) {
      errorCallback(e);
    }
  }
  void cancelRegistration() {
    _loginState = ApplicationLoginState.emailAddress;
    notifyListeners();
  }
  void registerAccount(String email,
      String displayName,
      String password,
      void Function(FirebaseAuthException e) errorCallback) async {
    try {
      var credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      await credential.user!.updateDisplayName(displayName);
    } on FirebaseAuthException catch(e) {
      errorCallback(e);
    }
  }
  void signOut() {
    FirebaseAuth.instance.signOut();
  }
  //
  Future<DocumentReference> addMessageToGuestBook(String message) {
    if (_loginState != ApplicationLoginState.loggedIn) {
      throw Exception('Must be logged in');
    }
    return FirebaseFirestore.instance
        .collection('guestbook')
        .add(<String, dynamic> {
        'text':message,
        'timestamp' : DateTime.now().microsecondsSinceEpoch,
        'name' : FirebaseAuth.instance.currentUser!.displayName,
        'userId' : FirebaseAuth.instance.currentUser!.uid
    });
  }
}
//
class GuestBookMessage {
  final String name;
  final String message;
  GuestBookMessage(this.name, this.message);
}
//
enum Attending { yes, no, unknown }
//
class GuestBook extends StatefulWidget {
  final FutureOr<void> Function(String message) addMessage;
  final List<GuestBookMessage> messages;
  const GuestBook({required this.addMessage, required this.messages});
  @override
  _GuestBookState createState() => _GuestBookState();
}

class _GuestBookState extends State<GuestBook> {
  final _formKey = GlobalKey<FormState>(debugLabel: '_GuestBookState');
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    print('${widget.messages}');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Form(
          key: _formKey,
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Leave a message',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Enter your message to continue';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              StyledButton(
                  child: Row(
                    children: const [
                      Icon(Icons.send),
                      SizedBox(
                        width: 4,
                      ),
                      Text('SEND'),
                    ],
                  ),
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      await widget.addMessage(_controller.text);
                      _controller.clear();
                    }
                  })
            ],
          ),
        ),
      ),
      const SizedBox(height: 8,),
      for(var message in widget.messages)
        Paragraph('${message.name}:${message.message}'),
        const SizedBox(height: 8,)
    ]
    );
  }
}
//
class YesNoSelection extends StatelessWidget {
  final Attending state;
  final void Function(Attending selection) onSelection;
  const YesNoSelection({required this.state, required this.onSelection});
  @override
  Widget build(BuildContext context) {
    switch (state) {
      case Attending.yes:
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child:Row(
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(elevation: 0),
                onPressed: () => onSelection(Attending.yes),
                child: const Text('YES'),
              ),
              const SizedBox(width: 8,),
              TextButton(
                onPressed: () => onSelection(Attending.no),
                child: const Text('NO'),
              ),
            ],
          ),
        );
      case Attending.no:
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              TextButton(
                onPressed: () => onSelection(Attending.yes),
                child: const Text('YES'),
              ),
              const SizedBox(width: 8,),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    elevation: 0
                  ),
                  onPressed: () => onSelection(Attending.no),
                  child: const Text('NO')
              ),
            ]
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              StyledButton(
                  child: const Text('YES'),
                  onPressed: () => onSelection(Attending.yes)
              ),
              const SizedBox(width: 8,),
              StyledButton(
                  child: const Text('NO'),
                  onPressed: () => onSelection(Attending.no))
            ],
          ),
        );
    }
  }
//
}