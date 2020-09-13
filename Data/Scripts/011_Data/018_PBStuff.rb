class PBStuff
  #Standardized lists of moves or abilities which are sometimes called
  ABILITYBLACKLIST = [PBAbilities::MULTITYPE,PBAbilities::COMATOSE,PBAbilities::DISGUISE,
   PBAbilities::SCHOOLING,PBAbilities::RKSSYSTEM,PBAbilities::IMPOSTER,PBAbilities::SHIELDSDOWN,
   PBAbilities::POWEROFALCHEMY,PBAbilities::RECEIVER,PBAbilities::TRACE,PBAbilities::FORECAST,
   PBAbilities::FLOWERGIFT,PBAbilities::ILLUSION,PBAbilities::WONDERGUARD,PBAbilities::ZENMODE,
   PBAbilities::STANCECHANGE,PBAbilities::POWERCONSTRUCT,PBAbilities::ICEFACE]
  FIXEDABILITIES = [PBAbilities::MULTITYPE,PBAbilities::ZENMODE,PBAbilities::STANCECHANGE,
   PBAbilities::SCHOOLING,PBAbilities::COMATOSE,PBAbilities::SHIELDSDOWN,PBAbilities::DISGUISE,
   PBAbilities::RKSSYSTEM,PBAbilities::POWERCONSTRUCT,PBAbilities::ICEFACE,PBAbilities::GULPMISSILE]
   #Blacklisted abilities USUALLY can't be copied.
   #Fixed abilities USUALLY can't be changed.

   #Standardized lists of moves with similar purposes/characteristics
   #(mostly just "stuff that gets called together")
  UNFREEZEMOVE = [PBMoves::FLAMEWHEEL,PBMoves::SACREDFIRE,PBMoves::FLAREBLITZ,
    PBMoves::FUSIONFLARE,PBMoves::SCALD,PBMoves::STEAMERUPTION,PBMoves::BURNUP]
  SWITCHOUTMOVE = [PBMoves::ROAR,PBMoves::WHIRLWIND,PBMoves::CIRCLETHROW,
    PBMoves::DRAGONTAIL,PBMoves::YAWN,PBMoves::PERISHSONG]
  SETUPMOVE = [PBMoves::SWORDSDANCE,PBMoves::DRAGONDANCE,PBMoves::CALMMIND,
    PBMoves::WORKUP,PBMoves::NASTYPLOT,PBMoves::TAILGLOW,PBMoves::BELLYDRUM,
    PBMoves::BULKUP,PBMoves::COIL,PBMoves::CURSE,PBMoves::GROWTH,
    PBMoves::HONECLAWS,PBMoves::QUIVERDANCE,PBMoves::SHELLSMASH]
  PROTECTMOVE = [PBMoves::PROTECT,PBMoves::DETECT,PBMoves::KINGSSHIELD,
    PBMoves::SPIKYSHIELD,PBMoves::BANEFULBUNKER]
  PROTECTIGNORINGMOVE = [PBMoves::FEINT,PBMoves::HYPERSPACEHOLE,
    PBMoves::HYPERSPACEFURY,PBMoves::SHADOWFORCE,PBMoves::PHANTOMFORCE]
  SCREENBREAKERMOVE = [PBMoves::DEFOG,PBMoves::BRICKBREAK,PBMoves::PSYCHICFANGS]
  CONTRARYBAITMOVE = [PBMoves::SUPERPOWER,PBMoves::OVERHEAT,PBMoves::DRACOMETEOR,
    PBMoves::LEAFSTORM,PBMoves::FLEURCANNON,PBMoves::PSYCHOBOOST]
  TWOTURNAIRMOVE = [PBMoves::BOUNCE,PBMoves::FLY,PBMoves::SKYDROP]
  PIVOTMOVE = [PBMoves::UTURN,PBMoves::VOLTSWITCH,PBMoves::PARTINGSHOT]
  DANCEMOVE = [PBMoves::QUIVERDANCE,PBMoves::DRAGONDANCE,PBMoves::FIERYDANCE,
    PBMoves::FEATHERDANCE,PBMoves::PETALDANCE,PBMoves::SWORDSDANCE,
    PBMoves::TEETERDANCE,PBMoves::LUNARDANCE,PBMoves::REVELATIONDANCE]
  BULLETMOVE = [PBMoves::ACIDSPRAY,PBMoves::AURASPHERE,PBMoves::BARRAGE,
    PBMoves::BULLETSEED,PBMoves::EGGBOMB,PBMoves::ELECTROBALL,PBMoves::ENERGYBALL,
    PBMoves::FOCUSBLAST,PBMoves::GYROBALL,PBMoves::ICEBALL,PBMoves::MAGNETBOMB,
    PBMoves::MISTBALL,PBMoves::MUDBOMB,PBMoves::OCTAZOOKA,PBMoves::ROCKWRECKER,
    PBMoves::SEARINGSHOT,PBMoves::SEEDBOMB,PBMoves::SHADOWBALL,PBMoves::SLUDGEBOMB,
    PBMoves::WEATHERBALL,PBMoves::ZAPCANNON,PBMoves::BEAKBLAST]

  BURNMOVE = [PBMoves::WILLOWISP,PBMoves::SACREDFIRE,PBMoves::INFERNO]
  PARAMOVE = [PBMoves::THUNDERWAVE,PBMoves::STUNSPORE,PBMoves::GLARE,
    PBMoves::NUZZLE,PBMoves::ZAPCANNON]
  SLEEPMOVE = [PBMoves::SPORE,PBMoves::SLEEPPOWDER,PBMoves::HYPNOSIS,PBMoves::DARKVOID,
    PBMoves::GRASSWHISTLE,PBMoves::LOVELYKISS,PBMoves::SING]
  POISONMOVE = [PBMoves::TOXIC,PBMoves::POISONPOWDER,PBMoves::POISONGAS,PBMoves::TOXICTHREAD]
  CONFUMOVE = [PBMoves::CONFUSERAY,PBMoves::SUPERSONIC,PBMoves::FLATTER,PBMoves::SWAGGER,
    PBMoves::SWEETKISS,PBMoves::TEETERDANCE,PBMoves::CHATTER,PBMoves::DYNAMICPUNCH]

  HEALFUNCTIONS =  [0xD5,0xD6,0xD7,0xD8,0xD9,0xDD,0xDE,0xDF,0xE3,0xE4,0x114,0x139,0x158,0x162,0x169,0x16C,0x172]

  #massive arrays of stuff that no one wants to see
  NATURALGIFTDAMAGE={
    100 => [:WATMELBERRY,:DURINBERRY,:BELUEBERRY,:LIECHIBERRY,:GANLONBERRY,:SALACBERRY,
            :PETAYABERRY,:APICOTBERRY,:LANSATBERRY,:STARFBERRY,:ENIGMABERRY,:MICLEBERRY,
            :CUSTAPBERRY,:JABOCABERRY,:ROWAPBERRY],
     90 => [:BLUKBERRY,:NANABBERRY,:WEPEARBERRY,:PINAPBERRY,:POMEGBERRY,:KELPSYBERRY,
            :QUALOTBERRY,:HONDEWBERRY,:GREPABERRY,:TAMATOBERRY,:CORNNBERRY,:MAGOSTBERRY,
            :RABUTABERRY,:NOMELBERRY,:SPELONBERRY,:PAMTREBERRY],
     80 => [:CHERIBERRY,:CHESTOBERRY,:PECHABERRY,:RAWSTBERRY,:ASPEARBERRY,:LEPPABERRY,
            :ORANBERRY,:PERSIMBERRY,:LUMBERRY,:SITRUSBERRY,:FIGYBERRY,:WIKIBERRY,
            :MAGOBERRY,:AGUAVBERRY,:IAPAPABERRY,:RAZZBERRY,:OCCABERRY,:PASSHOBERRY,
            :WACANBERRY,:RINDOBERRY,:YACHEBERRY,:CHOPLEBERRY,:KEBIABERRY,:SHUCABERRY,
            :COBABERRY,:PAYAPABERRY,:TANGABERRY,:CHARTIBERRY,:KASIBBERRY,:HABANBERRY,
            :COLBURBERRY,:BABIRIBERRY,:CHILANBERRY]} 
  FLINGDAMAGE={
    300 => [:MEMEONADE],
    130 => [:IRONBALL],
    100 => [:ARMORFOSSIL,:CLAWFOSSIL,:COVERFOSSIL,:DOMEFOSSIL,:HARDSTONE,:HELIXFOSSIL,
            :OLDAMBER,:PLUMEFOSSIL,:RAREBONE,:ROOTFOSSIL,:SKULLFOSSIL],
     90 => [:DEEPSEATOOTH,:DRACOPLATE,:DREADPLATE,:EARTHPLATE,:FISTPLATE,:FLAMEPLATE,
            :GRIPCLAW,:ICICLEPLATE,:INSECTPLATE,:IRONPLATE,:MEADOWPLATE,:MINDPLATE,
            :SKYPLATE,:SPLASHPLATE,:SPOOKYPLATE,:STONEPLATE,:THICKCLUB,:TOXICPLATE,
            :ZAPPLATE],
     80 => [:DAWNSTONE,:DUSKSTONE,:ELECTIRIZER,:MAGMARIZER,:ODDKEYSTONE,:OVALSTONE,
            :PROTECTOR,:QUICKCLAW,:RAZORCLAW,:SHINYSTONE,:STICKYBARB,:ASSAULTVEST],
     70 => [:BURNDRIVE,:CHILLDRIVE,:DOUSEDRIVE,:DRAGONFANG,:POISONBARB,:POWERANKLET,
            :POWERBAND,:POWERBELT,:POWERBRACER,:POWERLENS,:POWERWEIGHT,:SHOCKDRIVE],
     60 => [:ADAMANTORB,:DAMPROCK,:HEATROCK,:LUSTROUSORB,:MACHOBRACE,:ROCKYHELMET,
            :STICK,:AMPLIFIELDROCK,:ADRENALINEORB],
     50 => [:DUBIOUSDISC,:SHARPBEAK],
     40 => [:EVIOLITE,:ICYROCK,:LUCKYPUNCH,:PROTECTIVEPADS],
     30 => [:ABILITYURGE,:ABSORBBULB,:AMULETCOIN,:ANTIDOTE,:AWAKENING,:BALMMUSHROOM,
            :BERRYJUICE,:BIGMUSHROOM,:BIGNUGGET,:BIGPEARL,:BINDINGBAND,:BLACKBELT,
            :BLACKFLUTE,:BLACKGLASSES,:BLACKSLUDGE,:BLUEFLUTE,:BLUESHARD,:BURNHEAL,
            :CALCIUM,:CARBOS,:CASTELIACONE,:CELLBATTERY,:CHARCOAL,:CLEANSETAG,
            :COMETSHARD,:DAMPMULCH,:DEEPSEASCALE,:DIREHIT,:DIREHIT2,:DIREHIT3,
            :DRAGONSCALE,:EJECTBUTTON,:ELIXIR,:ENERGYPOWDER,:ENERGYROOT,:ESCAPEROPE,
            :ETHER,:EVERSTONE,:EXPSHARE,:FIRESTONE,:FLAMEORB,:FLOATSTONE,:FLUFFYTAIL,
            :FRESHWATER,:FULLHEAL,:FULLRESTORE,:GOOEYMULCH,:GREENSHARD,:GROWTHMULCH,
            :GUARDSPEC,:HEALPOWDER,:HEARTSCALE,:HONEY,:HPUP,:HYPERPOTION,:ICEHEAL,
            :IRON,:ITEMDROP,:ITEMURGE,:KINGSROCK,:LAVACOOKIE,:LEAFSTONE,:LEMONADE,
            :LIFEORB,:LIGHTBALL,:LIGHTCLAY,:LUCKYEGG,:MAGNET,:MAXELIXIR,:MAXETHER,
            :MAXPOTION,:MAXREPEL,:MAXREVIVE,:METALCOAT,:METRONOME,:MIRACLESEED,
            :MOOMOOMILK,:MOONSTONE,:MYSTICWATER,:NEVERMELTICE,:NUGGET,:OLDGATEAU,
            :PARLYZHEAL,:PEARL,:PEARLSTRING,:POKEDOLL,:POKETOY,:POTION,:PPMAX,:PPUP,
            :PRISMSCALE,:PROTEIN,:RAGECANDYBAR,:RARECANDY,:RAZORFANG,:REDFLUTE,
            :REDSHARD,:RELICBAND,:RELICCOPPER,:RELICCROWN,:RELICGOLD,:RELICSILVER,
            :RELICSTATUE,:RELICVASE,:REPEL,:RESETURGE,:REVIVALHERB,:REVIVE,:SACREDASH,
            :SCOPELENS,:SHELLBELL,:SHOALSALT,:SHOALSHELL,:SMOKEBALL,:SODAPOP,:SOULDEW,
            :SPELLTAG,:STABLEMULCH,:STARDUST,:STARPIECE,:SUNSTONE,:SUPERPOTION,
            :SUPERREPEL,:SWEETHEART,:THUNDERSTONE,:TINYMUSHROOM,:TOXICORB,
            :TWISTEDSPOON,:UPGRADE,:WATERSTONE,:WHITEFLUTE,:XACCURACY,:XACCURACY2,
            :XACCURACY3,:XACCURACY6,:XATTACK,:XATTACK2,:XATTACK3,:XATTACK6,:XDEFEND,
            :XDEFEND2,:XDEFEND3,:XDEFEND6,:XSPDEF,:XSPDEF2,:XSPDEF3,:XSPDEF6,:XSPECIAL,
            :XSPECIAL2,:XSPECIAL3,:XSPECIAL6,:XSPEED,:XSPEED2,:XSPEED3,:XSPEED6,
            :YELLOWFLUTE,:YELLOWSHARD,:ZINC,:BIGMALASADA,:ICESTONE],
     20 => [:CLEVERWING,:GENIUSWING,:HEALTHWING,:MUSCLEWING,:PRETTYWING,
            :RESISTWING,:SWIFTWING],
     10 => [:AIRBALLOON,:BIGROOT,:BLUESCARF,:BRIGHTPOWDER,:CHOICEBAND,:CHOICESCARF,
            :CHOICESPECS,:DESTINYKNOT,:EXPERTBELT,:FOCUSBAND,:FOCUSSASH,:FULLINCENSE,
            :GREENSCARF,:LAGGINGTAIL,:LAXINCENSE,:LEFTOVERS,:LUCKINCENSE,:MENTALHERB,
            :METALPOWDER,:MUSCLEBAND,:ODDINCENSE,:PINKSCARF,:POWERHERB,:PUREINCENSE,
            :QUICKPOWDER,:REAPERCLOTH,:REDCARD,:REDSCARF,:RINGTARGET,:ROCKINCENSE,
            :ROSEINCENSE,:SEAINCENSE,:SHEDSHELL,:SILKSCARF,:SILVERPOWDER,:SMOOTHROCK,
            :SOFTSAND,:SOOTHEBELL,:WAVEINCENSE,:WHITEHERB,:WIDELENS,:WISEGLASSES,
            :YELLOWSCARF,:ZOOMLENS,:BLUEMIC,:VANILLAIC,:STRAWBIC,:CHOCOLATEIC]}
end