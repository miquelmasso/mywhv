import 'dart:math';

import 'package:flutter/material.dart';

class TipsRandomPage extends StatefulWidget {
  const TipsRandomPage({super.key});

  @override
  State<TipsRandomPage> createState() => _TipsRandomPageState();
}

class _TipsRandomPageState extends State<TipsRandomPage> {
  final List<String> _tips = const [
    'Australia has more kangaroos than people; in many rural areas they are part of everyday life.',
'Traffic lights can take a long time in small towns: people are used to waiting.',
'It’s common to use free public barbecues in parks and beaches (electric BBQs).',
'In many places, payments are not monthly: rent and salaries are often weekly.',
'Australians use abbreviations a lot: arvo (afternoon), brekkie (breakfast), servo (gas station).',
'The sun is very strong: you can get burnt in 15 minutes even with clouds.',
'Wild animals are not an attraction: if you see a kangaroo on the road, slow down.',
'In small towns, everyone greets you even if they don’t know you.',
'Rural pubs are often the social centre of the town.',
'It’s normal to walk barefoot in supermarkets or petrol stations in coastal areas.',
'Distances are huge: “nearby” can mean a 3-hour drive.',
'Many jobs are not found online but by asking directly at the place.',
'Hostels often work as an informal job exchange.',
'Tap water is drinkable almost everywhere in the country.',
'Animals can appear on roads at night; driving in the dark is risky.',
'Most payments are made by card or mobile, even for very small amounts.',
'Australians value attitude more than experience in many jobs.',
'The “fair go” (equal opportunity) is a very important cultural value.',
'Public holidays are paid much much higher.',
'Many shared houses are found only through Facebook.',
'In remote areas, mobile coverage can disappear completely.',
'Cafés close early; after 3–4 pm it can be hard to find one open.',
'It’s normal to change cities and jobs often; it’s not frowned upon.',
'Many backpackers end up working in jobs they never imagined before coming.',
'In Australia, Christmas can mean 40°C, the beach, and a barbecue.',
'You can drive for hours and see more cows than cars.',
'Australians say “no worries” so often it becomes a lifestyle.',
'Flip-flops are called “thongs” and no one finds it weird.',
'Magpies will attack you like it’s a personal mission.',
'People apologise when you bump into them.',
'A “short walk” can turn into a 10 km hike.',
'You learn to check your shoes for spiders automatically.',
'Road trains are longer than some city blocks.',
'The word “mate” can mean friend, stranger, or warning.',
'You can live in a van and no one questions your life choices.',
'Sunburn is considered a beginner’s mistake.',
'Everyone knows someone who hit a kangaroo with their car.',
'Distances are measured in hours, not kilometres.',
'You can buy better coffee in the middle of nowhere than in big cities.',
'Job interviews can feel more like casual chats.',
'Rain can mean flooding… or nothing at all.',
'People will warn you about animals before welcoming you.',
'It’s normal to work with people from 10 different countries.',
'You stop being scared of insects… or you leave the country.',
'A “quick stop” at the servo always includes snacks.',
'Hats, sunscreen, and water are survival tools.',
'You learn that silence doesn’t mean awkwardness.',
'Everyone has a strong opinion about Vegemite.',
'You can see the Milky Way clearly in many places.',
'Weekends often start on Friday morning.',
'Living far away makes Australians very good planners.',
'Wildlife casually crosses highways like it owns them.',
'You realise how small Europe really is.',
'Australia teaches you patience, sun protection, and humility.',
'Kangaroos can’t walk backwards, which is why they’re on the Australian coat of arms.',
'Wombat poop is cube-shaped and it’s completely real.',
'Koalas sleep up to 20 hours a day.',
'Emus can sprint faster than most humans.',
'Dingoes can climb fences and open gates.',
'Platypuses lay eggs and produce milk at the same time.',
'Tasmanian devils scream so loudly it sounds unreal.',
'Some snakes are more scared of you than you are of them.',
'Saltwater crocodiles can live in the ocean and in rivers.',
'Kangaroos can drown dogs by luring them into water.',
'Magpies remember faces and hold grudges.',
'Spiders are so normal that people casually name them.',
'Echidnas have four-headed penises.',
'Wallabies can live happily inside national parks near cities.',
'Frogs can stop traffic during rainy nights.',
'Camels roam wild in the Australian desert.',
'Sharks sometimes appear surprisingly close to shore.',
'Goannas can climb trees effortlessly.',
'Some parrots swear better than humans.',
'Jellyfish can be deadly even when they look tiny.',
'Possums regularly invade houses at night.',
'Birds will steal your food without hesitation.',
'Snakes often enter houses looking for warmth.',
'Kangaroos can box each other like humans.',
'Octopuses can escape tanks and solve puzzles.',
'Cows on rural roads have absolute priority.',
'Spiders can be bigger than your hand.',
'Some fish can sting you without touching you.',
'Animals crossing the road is considered normal.',
'In Australia, wildlife always has the right of way.',
'Australia is the only continent without an active volcano.',
'The Dingo Fence stretches over 5,500 km – longer than the Great Wall of China.',
'Brisbane hosts an annual world championship for racing cockroaches.',
'Perth is the most isolated major city on Earth.',
'The Fitzroy River Turtle breathes through its bum to stay underwater longer.',
'Cassowaries have dagger-like claws and can jump to slash with them.',
'The male platypus has venomous spurs that can hospitalise a human.',
'There are pink lakes in Australia caused by algae and bacteria.',
'The longest golf course in the world is in Australia – over 1,300 km long.',
'Koalas have two opposable thumbs on each front paw.',
'Kangaroos can pause their pregnancy if conditions aren’t right.',
'Wombats have cube-shaped poop to stop it rolling away and mark territory.',
'The inland taipan has the most toxic venom of any snake – one bite could kill 100 people.',
'Australia has more venomous snakes than non-venomous ones.',
'The box jellyfish is considered the deadliest animal in the ocean.',
'Drop bears are a famous prank myth told to scare tourists – they don’t exist.',
'The world’s oldest continuous culture belongs to Aboriginal Australians – over 60,000 years.',
'Anna Creek Station is the largest cattle property – bigger than Israel or Belgium.',
'Some lakes in the outback turn bright pink and stay that way year-round.',
'You can find wild camels roaming the desert – descendants of ones brought for exploration.',
'Australia once declared war on emus and lost spectacularly – the birds outsmarted machine guns.',
'The Great Emu War is real history: soldiers fired thousands of rounds and the emus just kept winning.',
'Drop bears are a national prank – terrifying tourists with tales of carnivorous koalas that fall from trees.',
'Bob Hawke once sculled 2.5 pints of beer in 11 seconds as a uni record – then became Prime Minister.',
'Perth is so isolated you can literally land a plane in the city centre – nowhere else in the world allows it.',
'There’s an annual cockroach racing championship in Brisbane – with names like Guns ‘n’ Roaches.',
'The world’s longest golf course is here – 1,365 km, so you drive between holes for days.',
'Spiders can literally “rain” from the sky during ballooning season – baby spiders parachute everywhere.',
'Australians invented the wine cask (goon bag) – and yes, people still suck it through the spout at parties.',
'The Pitch Drop Experiment has been running since 1927 – only 9 drops have fallen, next one maybe never.',
'Some towns have signs warning about “aggressive magpies” like they’re gang members with a vendetta.',
'Everything is nicknamed: even the Prime Minister gets called ScoMo – short for Scott Morrison.',
'You can buy a slab of beer cheaper than a decent meal – priorities are priorities.',
'The outback has roads so straight you can fall asleep driving and still be on course hours later.',
'There’s a fence longer than the Great Wall of China built to stop dingoes – and it mostly works… sort of.',
'Koalas get high on eucalyptus – they’re basically nature’s stoners, sleeping 20 hours to recover.',
'People bet on which way a huntsman spider will run across the ceiling – entertainment is free.',
'The box jellyfish is so deadly they hand out vinegar at beaches like it’s ketchup for chips.',
'Some Australians still call thongs “thongs” and wonder why Americans giggle like schoolkids.',
'Everyone has a story about a kangaroo staring them down like it owns the footpath – because it does.',
  ];

  late String _currentTip;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _currentTip = _tips[_random.nextInt(_tips.length)];
  }

  void _nextTip() {
    setState(() {
      _currentTip = _tips[_random.nextInt(_tips.length)];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            children: [
              const Spacer(),
              const Text(
                'Did you know...',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 80),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.1)),
                  ),
                  child: Text(
                    _currentTip,
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _nextTip,
                icon: const Icon(Icons.shuffle),
                label: const Text('New fact'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
