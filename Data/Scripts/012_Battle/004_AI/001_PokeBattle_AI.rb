# AI skill levels:
#           0:     Wild Pokémon
#           1-31:  Basic trainer (young/inexperienced)
#           32-47: Some skill
#           48-99: High skill
#           100+:  Gym Leaders, E4, Champion, highest level
module PBTrainerAI
  # Minimum skill level to be in each AI category
  def PBTrainerAI.minimumSkill; 1; end
  def PBTrainerAI.mediumSkill; 32; end
  def PBTrainerAI.highSkill; 48; end
  def PBTrainerAI.bestSkill; 100; end   # Gym Leaders, E4, Champion
end



class PokeBattle_Battle
  attr_accessor :scores
  attr_accessor :targets
  attr_accessor :myChoices

################################################################################
# Get a score for each move being considered (trainer-owned Pokémon only).
# Moves with higher scores are more likely to be chosen.
################################################################################
  def pbGetMoveScore(move,attacker,opponent,skill=100,roughdamage=10,initialscores=[],scoreindex=-1)
    if roughdamage<1
      roughdamage=1
    end
    PBDebug.log(sprintf("%s: initial score: %d",PBMoves.getName(move.id),roughdamage)) if $INTERNAL
    skill=PBTrainerAI.minimumSkill if skill<PBTrainerAI.minimumSkill
    #score=(pbRoughDamage(move,attacker,opponent,skill,move.basedamage)*100/opponent.hp) #roughdamage
    score=roughdamage
    #Temporarly mega-ing pokemon if it can    #perry
    if pbCanMegaEvolve?(attacker.index)
      attacker.pokemon.makeMega
      attacker.pbUpdate(true)
      attacker.form=attacker.startform
      megaEvolved=true
    end
    #Little bit of prep before getting into the case statement
    oppitemworks = opponent.itemWorks?
    attitemworks = attacker.itemWorks?
    aimem = getAIMemory(skill,opponent.pokemonIndex)
    bettertype = move.pbBaseType(move.type)
    opponent=attacker.pbOppositeOpposing if !opponent
    opponent=opponent.pbPartner if opponent && opponent.isFainted?
    roles = pbGetMonRole(attacker,opponent,skill)
    if move.priority>0 || (move.basedamage==0 && !attacker.abilitynulled && attacker.ability == PBAbilities::PRANKSTER)
      if move.basedamage>0
        PBDebug.log(sprintf("Priority Check Begin")) if $INTERNAL
        fastermon = (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
        if fastermon
          PBDebug.log(sprintf("AI Pokemon is faster.")) if $INTERNAL
        else
          PBDebug.log(sprintf("Player Pokemon is faster.")) if $INTERNAL
        end
        if score>100
          if @doublebattle
            score*=1.3
          else
            if fastermon
              score*=1.3
            else
              score*=2
            end
          end
        else
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::STANCECHANGE)
            if !fastermon
              score*=0.7
            end
          end
        end
        movedamage = -1
        opppri = false
        pridam = -1
        if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          if aimem.length > 0
            for i in aimem
              tempdam = pbRoughDamage(i,opponent,attacker,skill,i.basedamage)
              if i.priority>0
                opppri=true
                if tempdam>pridam
                  pridam = tempdam
                end
              end
              if tempdam>movedamage
                movedamage = tempdam
              end
            end
          end
        end
        PBDebug.log(sprintf("Expected damage taken: %d",movedamage)) if $INTERNAL
        if !fastermon
          if movedamage>attacker.hp
            if @doublebattle
              score+=75
            else
              score+=150
            end
          end
        end
        if opppri
          score*=1.1
          if pridam>attacker.hp
            if fastermon
              score*=3
            else
              score*=0.5
            end
          end
        end
        if !fastermon && opponent.effects[PBEffects::TwoTurnAttack]>0
          score*=0
        end
        if $fefieldeffect==37
          score*=0
        end
        if !opponent.abilitynulled && (opponent.ability == PBAbilities::DAZZLING || opponent.ability == PBAbilities::QUEENLYMAJESTY)
          score*=0
        end
      end
      score*=0.2 if checkAImoves([PBMoves::QUICKGUARD],aimem)
      PBDebug.log(sprintf("Priority Check End")) if $INTERNAL
    elsif move.priority<0
      if fastermon
        score*=0.9
        if move.basedamage>0
          if opponent.effects[PBEffects::TwoTurnAttack]>0
            score*=2
          end
        end
      end
    end
    ##### Alter score depending on the move's function code ########################
    case move.function
      when 0x00 # No extra effect
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect == 30 # Mirror Arena
            if move.id==(PBMoves::DAZZLINGGLEAM)
              if (attacker.stages[PBStats::ACCURACY] < 0 || opponent.stages[PBStats::EVASION] > 0 ||
                (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER) || (oppitemworks && opponent.item == PBItems::LAXINCENSE) ||
                ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) ||
                ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL) ||
                opponent.vanished) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD) && !(!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD)
                score*=2
              end
            end
            if move.id==(PBMoves::BOOMBURST) || move.id==(PBMoves::HYPERVOICE)
              score*=0.3
            end
          end
          if $fefieldeffect == 33 # Flower Garden
            if $fecounter < 0
              if move.id==(PBMoves::CUT)
                goodmon = false
                for i in pbParty(attacker.index)
                  next if i.nil?
                  if i.hasType?(:GRASS) || i.hasType?(:BUG)
                    goodmon=true
                  end
                end
                if goodmon
                  score*=0.3
                else
                  score*=2
                end
              end
              if move.id==(PBMoves::PETALBLIZZARD) && $fecounter==4
                if @doublebattle
                  score*=1.5
                end
              end
            end
          end
          if $fefieldeffect == 23 # Cave
            if move.id==(PBMoves::POWERGEM)
              score*=1.3
              goodmon = false
              for i in pbParty(attacker.index)
                next if i.nil?
                if i.hasType?(:DRAGON) || i.hasType?(:FLYING) || i.hasType?(:ROCK)
                  goodmon=true
                end
              end
              if goodmon
                score*=1.3
              end
            end
          end
        end
      when 0x01 # Splash
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect == 21 # Water Surface
            if opponent.stages[PBStats::ACCURACY]==-6 || opponent.stages[PBStats::ACCURACY]>0 ||
              (!opponent.abilitynulled && opponent.ability == PBAbilities::CONTRARY)
              score=0
            else
              miniscore = 100
              if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
                miniscore*=1.3
              end
              count = -1
              sweepvar = false
              for i in pbParty(attacker.index)
                count+=1
                next if i.nil?
                temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
                if temprole.include?(PBMonRoles::SWEEPER)
                  sweepvar = true
                end
              end
              miniscore*=1.1 if sweepvar
              livecount = 0
              for i in pbParty(opponent.index)
                next if i.nil?
                livecount+=1 if i.hp!=0
              end
              if livecount==1 || (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || opponent.effects[PBEffects::MeanLook]>0
                miniscore*=1.4
              end
              if opponent.status==PBStatuses::BURN || opponent.status==PBStatuses::POISON
                miniscore*=1.3
              end
              if opponent.stages[PBStats::ACCURACY]<0
                minimini = 5*opponent.stages[PBStats::ACCURACY]
                minimini+=100
                minimini/=100.0
                miniscore*=minimini
              end
              miniscore/=100.0
              score*=miniscore
            end
          end
        end
      when 0x02 # Struggle
      when 0x03 # Sleep
        if opponent.pbCanSleep?(false) && opponent.effects[PBEffects::Yawn]==0
          miniscore=100
          miniscore*=1.3
          if attacker.pbHasMove?((PBMoves::DREAMEATER)) || attacker.pbHasMove?((PBMoves::NIGHTMARE)) ||
            (!attacker.abilitynulled && attacker.ability == PBAbilities::BADDREAMS)
            miniscore*=1.5
          end
          miniscore*=1.3 if attacker.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
          if attacker.pbHasMove?((PBMoves::LEECHSEED))
            miniscore*=1.3
          end
          if attacker.pbHasMove?((PBMoves::SUBSTITUTE))
            miniscore*=1.3
          end
          if opponent.hp==opponent.totalhp
            miniscore*=1.2
          end
          ministat = statchangecounter(opponent,1,7)
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          miniscore*=0.1 if checkAImoves([PBMoves::SLEEPTALK,PBMoves::SNORE],aimem)
          if !opponent.abilitynulled
            miniscore*=0.3 if opponent.ability == PBAbilities::NATURALCURE
            miniscore*=0.7 if opponent.ability == PBAbilities::MARVELSCALE
            miniscore*=0.5 if opponent.ability == PBAbilities::SYNCHRONIZE && attacker.status==0
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL) || roles.include?(PBMonRoles::CLERIC) || roles.include?(PBMonRoles::PIVOT)
            miniscore*=1.2
          end
          if (pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0)
            miniscore*=1.3
          end
          if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::POISONHEAL) && attacker.status==PBStatuses::POISON)
            miniscore*=1.2
          end
          if opponent.effects[PBEffects::Confusion]>0
            miniscore*=0.6
          end
          if opponent.effects[PBEffects::Attract]>=0
            miniscore*=0.7
          end
          if initialscores.length>0
            miniscore*=1.3 if hasbadmoves(initialscores,scoreindex,35)
          end
          if skill>=PBTrainerAI.bestSkill
            if move.id==(PBMoves::SING)
              if $fefieldeffect==6 # Big Top
                miniscore*=2
              end
              if (!opponent.abilitynulled && opponent.ability == PBAbilities::SOUNDPROOF)
                miniscore=0
              end
            end
            if move.id==(PBMoves::GRASSWHISTLE)
              if $fefieldeffect==2 # Grassy Terrain
                miniscore*=1.6
              end
              if (!opponent.abilitynulled && opponent.ability == PBAbilities::SOUNDPROOF)
                miniscore=0
              end
            end
          end
          if move.id==(PBMoves::SPORE)
            if (oppitemworks && opponent.item == PBItems::SAFETYGOGGLES) || (!opponent.abilitynulled && opponent.ability == PBAbilities::OVERCOAT) || opponent.pbHasType?(:GRASS)
              miniscore=0
            end
          end
          if skill>=PBTrainerAI.bestSkill
            if move.id==(PBMoves::SLEEPPOWDER)
              if $fefieldeffect==8 || $fefieldeffect==10 # Swamp or Corrosive
                miniscore*=2
              end
              if (oppitemworks && opponent.item == PBItems::SAFETYGOGGLES) || (!opponent.abilitynulled && opponent.ability == PBAbilities::OVERCOAT) || opponent.pbHasType?(:GRASS)
                miniscore=0
              end
              if $fefieldeffect==33 # Flower Garden
                miniscore*=1.3
                if @doublebattle
                  miniscore*= 2
                end
              end
            end
            if move.id==(PBMoves::HYPNOSIS)
              if $fefieldeffect==37 # Psychic Terrain
                miniscore*=1.8
              end
            end
            if move.id==(PBMoves::DARKVOID)
              if $fefieldeffect==4 || $fefieldeffect==35 # Dark Crystal or New World
                miniscore*=2
              elsif $fefieldeffect==25 # Crystal Cavern
                miniscore*=1.6
              end
            end
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::HYDRATION) && (pbWeather==PBWeather::RAINDANCE || $fefieldeffect == 21 || $fefieldeffect == 22)
            miniscore=0
          end
          if move.basedamage>0
            miniscore-=100
            if move.addlEffect.to_f != 100
              miniscore*=(move.addlEffect.to_f/100)
              if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
                miniscore*=2
              end
            end
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          else
            miniscore/=100.0
            score*=miniscore
          end
          if (move.id == PBMoves::DARKVOID) && !(attacker.species == PBSpecies::DARKRAI)
            score=0
          end
        else
          if move.basedamage==0
            score=0
          end
        end
      when 0x04 # Yawn
        if opponent.effects[PBEffects::Yawn]<=0 && opponent.pbCanSleep?(false)
          score*=1.2
          if attacker.pbHasMove?((PBMoves::DREAMEATER)) ||
            attacker.pbHasMove?((PBMoves::NIGHTMARE)) ||
            (!attacker.abilitynulled && attacker.ability == PBAbilities::BADDREAMS)
            score*=1.4
          end
          if opponent.hp==opponent.totalhp
            score*=1.2
          end
          ministat = statchangecounter(opponent,1,7)
          if ministat>0
            miniscore=10*ministat
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
          score*=0.1 if checkAImoves([PBMoves::SLEEPTALK,PBMoves::SNORE],aimem)
          if !opponent.abilitynulled
            score*=0.1 if opponent.ability == PBAbilities::NATURALCURE
            score*=0.8 if opponent.ability == PBAbilities::MARVELSCALE
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL) || roles.include?(PBMonRoles::CLERIC) || roles.include?(PBMonRoles::PIVOT)
            score*=1.2
          end
          if opponent.effects[PBEffects::Confusion]>0
            score*=0.4
          end
          if opponent.effects[PBEffects::Attract]>=0
            score*=0.5
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::HYDRATION) && (pbWeather==PBWeather::RAINDANCE || $fefieldeffect == 21 || $fefieldeffect == 22)
            miniscore=0
          end
          if initialscores.length>0
            score*=1.3 if hasbadmoves(initialscores,scoreindex,30)
          end
        else
          score=0
        end
      when 0x05 # Poison
        if opponent.pbCanPoison?(false)
          miniscore=100
          miniscore*=1.2
          ministat=0
          ministat+=opponent.stages[PBStats::DEFENSE]
          ministat+=opponent.stages[PBStats::SPDEF]
          ministat+=opponent.stages[PBStats::EVASION]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if !opponent.abilitynulled
            miniscore*=0.3 if opponent.ability == PBAbilities::NATURALCURE
            miniscore*=0.7 if opponent.ability == PBAbilities::MARVELSCALE
            miniscore*=0.2 if opponent.ability == PBAbilities::TOXICBOOST || opponent.ability == PBAbilities::GUTS || opponent.ability == PBAbilities::QUICKFEET
            miniscore*=0.1 if opponent.ability == PBAbilities::POISONHEAL || opponent.ability == PBAbilities::MAGICGUARD
            miniscore*=0.7 if opponent.ability == PBAbilities::SHEDSKIN
            miniscore*=1.1 if opponent.ability == PBAbilities::STURDY && move.basedamage>0
            miniscore*=0.5 if opponent.ability == PBAbilities::SYNCHRONIZE && attacker.status==0 && !attacker.pbHasType?(:POISON) && !attacker.pbHasType?(:STEEL)
          end
          miniscore*=0.2 if checkAImoves([PBMoves::FACADE],aimem)
          miniscore*=0.1 if checkAImoves([PBMoves::REST],aimem)
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            miniscore*=1.5
          end
          if initialscores.length>0
            miniscore*=1.2 if hasbadmoves(initialscores,scoreindex,30)
          end
          if attacker.pbHasMove?((PBMoves::VENOSHOCK)) ||
            attacker.pbHasMove?((PBMoves::VENOMDRENCH)) ||
            (!attacker.abilitynulled && attacker.ability == PBAbilities::MERCILESS)
            miniscore*=1.6
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          if skill>=PBTrainerAI.bestSkill
            if move.id==(PBMoves::SLUDGEWAVE)
              if $fefieldeffect==21 || $fefieldeffect==22 # Water Surface/Underwater
                poisonvar=false
                watervar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:WATER)
                    watervar=true
                  end
                  if mon.hasType?(:POISON)
                    poisonvar=true
                  end
                end
                if poisonvar && !watervar
                  miniscore*=1.75
                end
              end
            end
            if move.id==(PBMoves::SMOG) || move.id==(PBMoves::POISONGAS)
              if $fefieldeffect==3 # Misty Terrain
                poisonvar=false
                fairyvar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:FAIRY)
                    fairyvar=true
                  end
                  if mon.hasType?(:POISON)
                    poisonvar=true
                  end
                end
                if poisonvar && !fairyvar
                  miniscore*=1.75
                end
              end
            end
            if move.id==(PBMoves::POISONPOWDER)
              if $fefieldeffect==10 || ($fefieldeffect==33 && $fecounter>0)  # Corrosive/Flower Garden Stage 2+
                miniscore*=1.25
              end
              if (oppitemworks && opponent.item == PBItems::SAFETYGOGGLES) || (!opponent.abilitynulled && opponent.ability == PBAbilities::OVERCOAT) || opponent.pbHasType?(:GRASS)
                miniscore=0
              end
            end
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::HYDRATION) && (pbWeather==PBWeather::RAINDANCE || $fefieldeffect == 21 || $fefieldeffect == 22)
            miniscore=0
          end
          if move.basedamage>0
            miniscore-=100
            if move.addlEffect.to_f != 100
              miniscore*=(move.addlEffect.to_f/100)
              if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
                miniscore*=2
              end
            end
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          else
            miniscore/=100.0
            score*=miniscore
          end
        else
          poisonvar=false
          fairyvar=false
          for mon in pbParty(attacker.index)
            next if mon.nil?
            if mon.hasType?(:FAIRY)
              fairyvar=true
            end
            if mon.hasType?(:POISON)
              poisonvar=true
            end
          end
          if skill>=PBTrainerAI.bestSkill
            if move.id==(PBMoves::SMOG)
              if $fefieldeffect==3 # Misty Terrain
                if poisonvar && !fairyvar
                  score*=1.75
                end
              end
            end
          end
          if move.basedamage<=0
            score=0
            if skill>=PBTrainerAI.bestSkill
              if move.id==(PBMoves::SMOG) || move.id==(PBMoves::POISONGAS)
                if $fefieldeffect==3 # Misty Terrain
                  if poisonvar && !fairyvar
                    score = 15
                  end
                end
              end
            end
          end
        end
      when 0x06 # Toxic
        if opponent.pbCanPoison?(false)
          miniscore=100
          miniscore*=1.3
          ministat=0
          ministat+=opponent.stages[PBStats::DEFENSE]
          ministat+=opponent.stages[PBStats::SPDEF]
          ministat+=opponent.stages[PBStats::EVASION]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
            PBDebug.log(sprintf("kll2")) if $INTERNAL
          end
          miniscore*=2 if checkAIhealing(aimem)
          if !opponent.abilitynulled
            miniscore*=0.2 if opponent.ability == PBAbilities::NATURALCURE
            miniscore*=0.8 if opponent.ability == PBAbilities::MARVELSCALE
            miniscore*=0.2 if opponent.ability == PBAbilities::TOXICBOOST || opponent.ability == PBAbilities::GUTS || opponent.ability == PBAbilities::QUICKFEET
            miniscore*=0.1 if opponent.ability == PBAbilities::POISONHEAL || opponent.ability == PBAbilities::MAGICGUARD
            miniscore*=0.7 if opponent.ability == PBAbilities::SHEDSKIN
            miniscore*=1.1 if opponent.ability == PBAbilities::STURDY && move.basedamage>0
            miniscore*=0.5 if opponent.ability == PBAbilities::SYNCHRONIZE && attacker.status==0 && !attacker.pbHasType?(:POISON) && !attacker.pbHasType?(:STEEL)
          end
          miniscore*=0.3 if checkAImoves([PBMoves::FACADE],aimem)
          miniscore*=0.1 if checkAImoves([PBMoves::REST],aimem)
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            miniscore*=1.6
          end
          if initialscores.length>0
            miniscore*=1.3 if hasbadmoves(initialscores,scoreindex,30)
          end
          if attacker.pbHasMove?((PBMoves::VENOSHOCK)) ||
            attacker.pbHasMove?((PBMoves::VENOMDRENCH)) ||
            (!attacker.abilitynulled && attacker.ability == PBAbilities::MERCILESS)
            miniscore*=1.6
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.1
          end
          if move.id==(PBMoves::TOXIC)
            if attacker.pbHasType?(:POISON)
              miniscore*=1.1
            end
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::HYDRATION) && (pbWeather==PBWeather::RAINDANCE || $fefieldeffect == 21 || $fefieldeffect == 22)
            miniscore=0
          end
          if move.basedamage>0
            miniscore-=100
            if move.addlEffect.to_f != 100
              miniscore*=(move.addlEffect.to_f/100)
              if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
                miniscore*=2
              end
            end
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          else
            miniscore/=100.0
            score*=miniscore
          end
        else
          if move.basedamage<=0
            PBDebug.log(sprintf("KILL")) if $INTERNAL
            score=0
          end
        end
      when 0x07 # Paralysis
        wavefail=false
        if move.id==(PBMoves::THUNDERWAVE)
          typemod=move.pbTypeModifier(move.type,attacker,opponent)
          if typemod==0
            wavefail=true
          end
        end
        if opponent.pbCanParalyze?(false) && !wavefail
          miniscore=100
          miniscore*=1.1 if attacker.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
          if opponent.hp==opponent.totalhp
            miniscore*=1.2
          end
          ministat=0
          ministat+=opponent.stages[PBStats::ATTACK]
          ministat+=opponent.stages[PBStats::SPATK]
          ministat+=opponent.stages[PBStats::SPEED]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if !opponent.abilitynulled
            miniscore*=0.3 if opponent.ability == PBAbilities::NATURALCURE
            miniscore*=0.5 if opponent.ability == PBAbilities::MARVELSCALE
            miniscore*=0.2 if opponent.ability == PBAbilities::GUTS || opponent.ability == PBAbilities::QUICKFEET
            miniscore*=0.7 if opponent.ability == PBAbilities::SHEDSKIN
            miniscore*=0.5 if opponent.ability == PBAbilities::SYNCHRONIZE && attacker.status==0
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL) || roles.include?(PBMonRoles::PIVOT)
            miniscore*=1.2
          end
          if roles.include?(PBMonRoles::TANK)
            miniscore*=1.3
          end
          if pbRoughStat(opponent,PBStats::SPEED,skill)>attacker.pbSpeed && (pbRoughStat(opponent,PBStats::SPEED,skill)/2.0)<attacker.pbSpeed && @trickroom==0
            miniscore*=1.5
          end
          if pbRoughStat(opponent,PBStats::SPATK,skill)>pbRoughStat(opponent,PBStats::ATTACK,skill)
            miniscore*=1.1
          end
          count = -1
          sweepvar = false
          for i in pbParty(attacker.index)
            count+=1
            next if i.nil?
            temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
            if temprole.include?(PBMonRoles::SWEEPER)
              sweepvar = true
            end
          end
          miniscore*=1.1 if sweepvar
          if opponent.effects[PBEffects::Confusion]>0
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Attract]>=0
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          #if move.id==(PBMoves::NUZZLE)
          #  score+=40
          #end
          if skill>=PBTrainerAI.bestSkill
            if move.id==(PBMoves::ZAPCANNON)
              if $fefieldeffect==18 # Short-Circuit
                miniscore*=1.3
              end
            end
            if move.id==(PBMoves::DISCHARGE)
              ghostvar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:GHOST)
                  ghostvar=true
                end
              end
              if $fefieldeffect==17# Factory
                miniscore*=1.1
                if ghostvar
                  miniscore*=1.3
                end
              end
              if $fefieldeffect==18  # Short-Circuit
                miniscore*=1.1
                if ghostvar
                  miniscore*=0.8
                end
              end
            end
            if move.id==(PBMoves::STUNSPORE)
              if $fefieldeffect==10 || ($fefieldeffect==33 && $fecounter>0)  # Corrosive/Flower Garden Stage 2+
                miniscore*=1.25
              end
              if (oppitemworks && opponent.item == PBItems::SAFETYGOGGLES) || (!opponent.abilitynulled && opponent.ability == PBAbilities::OVERCOAT) || opponent.pbHasType?(:GRASS)
                miniscore=0
              end
            end
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::HYDRATION) && (pbWeather==PBWeather::RAINDANCE || $fefieldeffect == 21 || $fefieldeffect == 22)
            miniscore=0
          end
          if move.basedamage>0
            miniscore-=100
            if move.addlEffect.to_f != 100
              miniscore*=(move.addlEffect.to_f/100)
              if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
                miniscore*=2
              end
            end
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          else
            miniscore/=100.0
            score*=miniscore
          end
        else
          if move.basedamage==0
            score=0
          end
        end
      when 0x08 # Thunder + Paralyze
        if opponent.pbCanParalyze?(false) && opponent.effects[PBEffects::Yawn]<=0
          miniscore=100
          miniscore*=1.1 if attacker.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
          if opponent.hp==opponent.totalhp
            miniscore*=1.2
          end
          ministat=0
          ministat+=opponent.stages[PBStats::ATTACK]
          ministat+=opponent.stages[PBStats::SPATK]
          ministat+=opponent.stages[PBStats::SPEED]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if !opponent.abilitynulled
            miniscore*=0.3 if opponent.ability == PBAbilities::NATURALCURE
            miniscore*=0.5 if opponent.ability == PBAbilities::MARVELSCALE
            miniscore*=0.2 if opponent.ability == PBAbilities::GUTS || opponent.ability == PBAbilities::QUICKFEET
            miniscore*=0.7 if opponent.ability == PBAbilities::SHEDSKIN
            miniscore*=0.5 if opponent.ability == PBAbilities::SYNCHRONIZE && attacker.status==0
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL) || roles.include?(PBMonRoles::PIVOT)
            miniscore*=1.2
          end
          if roles.include?(PBMonRoles::TANK)
            miniscore*=1.3
          end
          if pbRoughStat(opponent,PBStats::SPEED,skill)>attacker.pbSpeed && (pbRoughStat(opponent,PBStats::SPEED,skill)/2.0)<attacker.pbSpeed && @trickroom==0
            miniscore*=1.5
          end
          if pbRoughStat(opponent,PBStats::SPATK,skill)>pbRoughStat(opponent,PBStats::ATTACK,skill)
            miniscore*=1.1
          end
          count = -1
          sweepvar = false
          for i in pbParty(attacker.index)
            count+=1
            next if i.nil?
            temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
            if temprole.include?(PBMonRoles::SWEEPER)
              sweepvar = true
            end
          end
          miniscore*=1.1 if sweepvar
          if opponent.effects[PBEffects::Confusion]>0
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Attract]>=0
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
          invulmove=$pkmn_move[opponent.effects[PBEffects::TwoTurnAttack]][0]
          if invulmove==0xC9 || invulmove==0xCC || invulmove==0xCE
            if (pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0)
              score*=2
            end
          end
          if (pbRoughStat(opponent,PBStats::SPEED,skill)>attacker.pbSpeed) ^ (@trickroom!=0)
            score*=1.2 if checkAImoves(PBStuff::TWOTURNAIRMOVE,aimem)
          end
        end
      when 0x09 # Paralysis + Flinch
        if opponent.pbCanParalyze?(false)
          miniscore=100
          miniscore*=1.1 if attacker.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
          if opponent.hp==opponent.totalhp
            miniscore*=1.1
          end
          ministat=0
          ministat+=opponent.stages[PBStats::ATTACK]
          ministat+=opponent.stages[PBStats::SPATK]
          ministat+=opponent.stages[PBStats::SPEED]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if !opponent.abilitynulled
            miniscore*=0.3 if opponent.ability == PBAbilities::NATURALCURE
            miniscore*=0.5 if opponent.ability == PBAbilities::MARVELSCALE
            miniscore*=0.2 if opponent.ability == PBAbilities::GUTS || opponent.ability == PBAbilities::QUICKFEET
            miniscore*=0.7 if opponent.ability == PBAbilities::SHEDSKIN
            miniscore*=0.5 if opponent.ability == PBAbilities::SYNCHRONIZE && attacker.status==0
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL) || roles.include?(PBMonRoles::PIVOT)
            miniscore*=1.2
          end
          if roles.include?(PBMonRoles::TANK)
            miniscore*=1.1
          end
          if pbRoughStat(opponent,PBStats::SPEED,skill)>attacker.pbSpeed && (pbRoughStat(opponent,PBStats::SPEED,skill)/2)<attacker.pbSpeed && @trickroom==0
            miniscore*=1.1
          end
          if pbRoughStat(opponent,PBStats::SPATK,skill)>pbRoughStat(opponent,PBStats::ATTACK,skill)
            miniscore*=1.1
          end
          count = -1
          sweepvar = false
          for i in pbParty(attacker.index)
            count+=1
            next if i.nil?
            temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
            if temprole.include?(PBMonRoles::SWEEPER)
              sweepvar = true
            end
          end
          miniscore*=1.1 if sweepvar
          if opponent.effects[PBEffects::Confusion]>0
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Attract]>=0
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          if opponent.effects[PBEffects::Substitute]==0 && !(!opponent.abilitynulled && opponent.ability == PBAbilities::INNERFOCUS)
            if (pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0)
              miniscore*=1.1
              if skill>=PBTrainerAI.bestSkill
                if $fefieldeffect==14 # Rocky
                  miniscore*=1.1
                end
              end
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::STEADFAST)
              miniscore*=0.3
            end
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
        end
      when 0x0A # Burn
        if opponent.pbCanBurn?(false)
          miniscore=100
          miniscore*=1.2
          ministat=0
          ministat+=opponent.stages[PBStats::ATTACK]
          ministat+=opponent.stages[PBStats::SPATK]
          ministat+=opponent.stages[PBStats::SPEED]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if !opponent.abilitynulled
            miniscore*=0.3 if opponent.ability == PBAbilities::NATURALCURE
            miniscore*=0.7 if opponent.ability == PBAbilities::MARVELSCALE
            miniscore*=0.1 if opponent.ability == PBAbilities::GUTS || opponent.ability == PBAbilities::FLAREBOOST
            miniscore*=0.7 if opponent.ability == PBAbilities::SHEDSKIN
            miniscore*=0.5 if opponent.ability == PBAbilities::SYNCHRONIZE && attacker.status==0
            miniscore*=0.5 if opponent.ability == PBAbilities::MAGICGUARD
            miniscore*=0.3 if opponent.ability == PBAbilities::QUICKFEET
            miniscore*=1.1 if opponent.ability == PBAbilities::STURDY && move.basedamage>0
          end
          miniscore*=0.1 if checkAImoves([PBMoves::REST],aimem)
          miniscore*=0.3 if checkAImoves([PBMoves::FACADE],aimem)
          if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
            miniscore*=1.4
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          if skill>=PBTrainerAI.bestSkill
            if move.id==(PBMoves::HEATWAVE) || move.id==(PBMoves::SEARINGSHOT) || move.id==(PBMoves::LAVAPLUME)
              if $fefieldeffect==2 || $fefieldeffect==15 || ($fefieldeffect==33 && $fecounter>1)  # Grassy/Forest/Flower Garden
                roastvar=false
                firevar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:GRASS) || mon.hasType?(:BUG)
                    roastvar=true
                  end
                  if mon.hasType?(:FIRE)
                    firevar=true
                  end
                end
                if firevar && !roastvar
                  miniscore*=2
                end
              end
              if $fefieldeffect==16 # Superheated
                firevar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:FIRE)
                    firevar=true
                  end
                end
                if firevar
                  miniscore*=2
                end
              end
              if $fefieldeffect==11 # Corrosive Mist
                poisonvar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:POISON)
                    poisonvar=true
                  end
                end
                if !poisonvar
                  miniscore*=1.2
                end
                if (attacker.hp.to_f)/attacker.totalhp<0.2
                  miniscore*=2
                end
                count=0
                for mon in pbParty(opponent.index)
                  next if mon.nil?
                  count+=1 if mon.hp>0
                end
                if count==1
                  miniscore*=5
                end
              end
              if $fefieldeffect==13 || $fefieldeffect==28 # Icy/Snowy Mountain
                icevar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:ICE)
                    icevar=true
                  end
                end
                if !icevar
                  miniscore*=1.5
                end
              end
            end
            if move.id==(PBMoves::WILLOWISP)
              if $fefieldeffect==7 # Burning
                miniscore*=1.5
              end
            end
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::HYDRATION) && (pbWeather==PBWeather::RAINDANCE || $fefieldeffect == 21 || $fefieldeffect == 22)
            miniscore=0
          end
          if move.basedamage>0
            miniscore-=100
            if move.addlEffect.to_f != 100
              miniscore*=(move.addlEffect.to_f/100)
              if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
                miniscore*=2
              end
            end
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          else
            miniscore/=100.0
            score*=miniscore
          end
        else
          if move.basedamage==0
            score=0
          end
        end
      when 0x0B # Burn + Flinch
        if opponent.pbCanBurn?(false)
          miniscore=100
          ministat=0
          ministat+=opponent.stages[PBStats::ATTACK]
          ministat+=opponent.stages[PBStats::SPATK]
          ministat+=opponent.stages[PBStats::SPEED]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if !opponent.abilitynulled
            miniscore*=0.3 if opponent.ability == PBAbilities::NATURALCURE
            miniscore*=0.7 if opponent.ability == PBAbilities::MARVELSCALE
            miniscore*=0.1 if opponent.ability == PBAbilities::GUTS || opponent.ability == PBAbilities::FLAREBOOST
            miniscore*=0.7 if opponent.ability == PBAbilities::SHEDSKIN
            miniscore*=0.5 if opponent.ability == PBAbilities::SYNCHRONIZE && attacker.status==0
            miniscore*=0.5 if opponent.ability == PBAbilities::MAGICGUARD
            miniscore*=0.3 if opponent.ability == PBAbilities::QUICKFEET
            miniscore*=1.1 if opponent.ability == PBAbilities::STURDY && move.basedamage>0
          end
          miniscore*=0.1 if checkAImoves([PBMoves::REST],aimem)
          miniscore*=0.3 if checkAImoves([PBMoves::FACADE],aimem)
          if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
            miniscore*=1.4
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          if opponent.effects[PBEffects::Substitute]==0 && !(!opponent.abilitynulled && opponent.ability == PBAbilities::INNERFOCUS)
            if (pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0)
              miniscore*=1.1
              if skill>=PBTrainerAI.bestSkill
                if $fefieldeffect==14 # Rocky
                  miniscore*=1.1
                end
              end
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::STEADFAST)
              miniscore*=0.3
            end
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
        end
      when 0x0C # Freeze
        if opponent.pbCanFreeze?(false)
          miniscore=100
          miniscore*=1.2
          miniscore*=0 if checkAImoves(PBStuff::UNFREEZEMOVE,aimem)
          miniscore*=1.2 if attacker.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
          miniscore*=1.2 if checkAIhealing(aimem)
          ministat = statchangecounter(opponent,1,7)
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if !opponent.abilitynulled
            miniscore*=0.3 if opponent.ability == PBAbilities::NATURALCURE
            miniscore*=0.8 if opponent.ability == PBAbilities::MARVELSCALE
            miniscore*=0.5 if opponent.ability == PBAbilities::SYNCHRONIZE && attacker.status==0
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==13 # Icy Field
              miniscore*=2
            end
          end
          score*=miniscore
        end
      when 0x0D # Blizzard Freeze
        if opponent.pbCanFreeze?(false)
          miniscore=100
          miniscore*=1.4
          miniscore*=0 if checkAImoves(PBStuff::UNFREEZEMOVE,aimem)
          miniscore*=1.3 if attacker.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
          miniscore*=1.2 if checkAIhealing(aimem)
          ministat = statchangecounter(opponent,1,7)
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if !opponent.abilitynulled
            miniscore*=0.3 if opponent.ability == PBAbilities::NATURALCURE
            miniscore*=0.8 if opponent.ability == PBAbilities::MARVELSCALE
            miniscore*=0.5 if opponent.ability == PBAbilities::SYNCHRONIZE && attacker.status==0
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==13 # Icy Field
              miniscore*=2
            end
          end
          score*=miniscore
        #  if pbWeather == PBWeather::HAIL
        #    score*=1.3
        #  end
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==26 # Murkwater Surface
              icevar=false
              murkvar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:ICE)
                  icevar=true
                end
                if mon.hasType?(:POISON) || mon.hasType?(:WATER)
                  murkvar=true
                end
              end
              if icevar
                score*=1.3
              end
              if !murkvar
                score*=1.3
              else
                score*=0.5
              end
            end
            if $fefieldeffect==21 # Water Surface
              icevar=false
              wayervar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:ICE)
                  icevar=true
                end
                if mon.hasType?(:WATER)
                  watervar=true
                end
              end
              if icevar
                score*=1.3
              end
              if !watervar
                score*=1.3
              else
                score*=0.5
              end
            end
            if $fefieldeffect==27 # Mountain
              icevar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:ICE)
                  icevar=true
                end
              end
              if icevar
                score*=1.3
              end
            end
            if $fefieldeffect==16 # Superheated Field
              icevar=false
              firevar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:ICE)
                  icevar=true
                end
                if mon.hasType?(:FIRE)
                  firevar=true
                end
              end
              if icevar
                score*=1.3
              end
              if !firevar
                score*=1.3
              else
                score*=0.5
              end
            end
            if $fefieldeffect==24 # Glitch
              score*=1.2
            end
          end
        end
      when 0x0E # Freeze + Flinch
        if opponent.pbCanFreeze?(false)
          miniscore=100
          miniscore*=1.1
          miniscore*=0 if checkAImoves(PBStuff::UNFREEZEMOVE,aimem)
          miniscore*=1.3 if attacker.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
          miniscore*=1.2 if checkAIhealing(aimem)
          ministat = statchangecounter(opponent,1,7)
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if !opponent.abilitynulled
            miniscore*=0.3 if opponent.ability == PBAbilities::NATURALCURE
            miniscore*=0.8 if opponent.ability == PBAbilities::MARVELSCALE
            miniscore*=0.5 if opponent.ability == PBAbilities::SYNCHRONIZE && attacker.status==0
          end
          if opponent.effects[PBEffects::Substitute]==0 && !(!opponent.abilitynulled && opponent.ability == PBAbilities::INNERFOCUS)
            if (pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0)
              miniscore*=1.1
              if skill>=PBTrainerAI.bestSkill
                if $fefieldeffect==14 # Rocky
                  miniscore*=1.1
                end
              end
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::STEADFAST)
              miniscore*=0.3
            end
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==13 # Icy Field
              miniscore*=2
            end
          end
          score*=miniscore
        end
      when 0x0F # Flinch
        if opponent.effects[PBEffects::Substitute]==0 && !(!opponent.abilitynulled && opponent.ability == PBAbilities::INNERFOCUS)
          if (pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed)  ^ (@trickroom!=0)
            miniscore=100
            miniscore*=1.3
            if skill>=PBTrainerAI.bestSkill
              if $fefieldeffect==14 # Rocky
                miniscore*=1.2
              end
              if move.id==(PBMoves::DARKPULSE) && $fefieldeffect==25 # Crystal Cavern
                miniscore*=1.3
                dragonvar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:DRAGON)
                    dragonvar=true
                  end
                end
                if !dragonvar
                  miniscore*=1.3
                end
              end
            end
            if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || (pbWeather == PBWeather::HAIL && !opponent.pbHasType?(:ICE)) || (pbWeather == PBWeather::SANDSTORM && !opponent.pbHasType?(:ROCK) && !opponent.pbHasType?(:GROUND) && !opponent.pbHasType?(:STEEL)) || opponent.effects[PBEffects::LeechSeed]>-1 || opponent.effects[PBEffects::Curse]
              miniscore*=1.1
              if opponent.effects[PBEffects::Toxic]>0
                miniscore*=1.2
              end
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::STEADFAST)
              miniscore*=0.3
            end
            miniscore-=100
            if move.addlEffect.to_f != 100
              miniscore*=(move.addlEffect.to_f/100)
              if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
                miniscore*=2
              end
            end
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
        end
      when 0x10 # Stomp
        if opponent.effects[PBEffects::Substitute]==0 && !(!opponent.abilitynulled && opponent.ability == PBAbilities::INNERFOCUS)
          if (pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0)
            miniscore=100
            miniscore*=1.3
            if skill>=PBTrainerAI.bestSkill
              if $fefieldeffect==14 # Rocky
                miniscore*=1.2
              end
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::STEADFAST)
              miniscore*=0.3
            end
            miniscore-=100
            if move.addlEffect.to_f != 100
              miniscore*=(move.addlEffect.to_f/100)
              if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
                miniscore*=2
              end
            end
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
        end
        score*=2 if opponent.effects[PBEffects::Minimize]
      when 0x11 # Snore
        if attacker.status==PBStatuses::SLEEP
          score*=2
          if opponent.effects[PBEffects::Substitute]!=0
            score*=1.3
          end
          if !(!opponent.abilitynulled && opponent.ability == PBAbilities::INNERFOCUS) && ((pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0))
            miniscore=100
            miniscore*=1.3
            if skill>=PBTrainerAI.bestSkill
              if $fefieldeffect==14 # Rocky
                miniscore*=1.2
              end
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::STEADFAST)
              miniscore*=0.3
            end
            miniscore-=100
            if move.addlEffect.to_f != 100
              miniscore*=(move.addlEffect.to_f/100)
              if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
                miniscore*=2
              end
            end
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
        else
          score=0
        end
      when 0x12 # Fake Out
        if attacker.turncount==0
          if opponent.effects[PBEffects::Substitute]==0 && !(!opponent.abilitynulled && opponent.ability == PBAbilities::INNERFOCUS)
            if score>1
              score+=115
            end
            if skill>=PBTrainerAI.bestSkill
              if $fefieldeffect==14 # Rocky
                score*=1.2
              end
            end
            if @doublebattle
              score*=0.7
            end
            if (attitemworks && attacker.item == PBItems::NORMALGEM)
              score*=1.1
              if (!attacker.abilitynulled && attacker.ability == PBAbilities::UNBURDEN)
                score*=1.5
              end
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::STEADFAST)
              score*=0.3
            end
            score*=0.3 if checkAImoves([PBMoves::ENCORE],aimem)
          end
        else
          score=0
        end
      when 0x13 # Confusion
        if opponent.pbCanConfuse?(false)
          miniscore=100
          miniscore*=1.2
          ministat=0
          ministat+=opponent.stages[PBStats::ATTACK]
          if ministat>0
            minimini=10*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
            miniscore*=1.2
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            miniscore*=1.3
          end
          if opponent.effects[PBEffects::Attract]>=0
            miniscore*=1.1
          end
          if opponent.status==PBStatuses::PARALYSIS
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Yawn]>0 || opponent.status==PBStatuses::SLEEP
            miniscore*=0.4
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::TANGLEDFEET)
            miniscore*=0.7
          end
          if attacker.pbHasMove?((PBMoves::SUBSTITUTE))
            miniscore*=1.2
            if attacker.effects[PBEffects::Substitute]>0
              miniscore*=1.3
            end
          end
          if skill>=PBTrainerAI.bestSkill
            if move.id==(PBMoves::SIGNALBEAM)
              if $fefieldeffect==30 # Mirror Arena
                if (attacker.stages[PBStats::ACCURACY] < 0 || opponent.stages[PBStats::EVASION] > 0 ||
                  (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER) || (oppitemworks && opponent.item == PBItems::LAXINCENSE) ||
                  ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) ||
                  ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL) ||
                  opponent.vanished) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD) && !(!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD)
                  miniscore*=2
                end
              end
            end
            if move.id==(PBMoves::SWEETKISS)
              if $fefieldeffect==3 # Misty
                miniscore*=1.25
              end
              if $fefieldeffect==31 # Fairy Tale
                if opponent.status==PBStatuses::SLEEP
                  miniscore*=0.2
                end
              end
            end
          end
          if initialscores.length>0
            miniscore*=1.4 if hasbadmoves(initialscores,scoreindex,40)
          end
          if move.basedamage>0
            miniscore-=100
            if move.addlEffect.to_f != 100
              miniscore*=(move.addlEffect.to_f/100)
              if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
                miniscore*=2
              end
            end
            miniscore+=100
          end
          miniscore/=100.0
          score*=miniscore
        else
          if move.basedamage<=0
            score=0
          end
        end
      when 0x14 # Chatter
        #This is no longer used, Chatter works off of the standard confusion
        #function code, 0x13
      when 0x15 # Hurricane
        if opponent.pbCanConfuse?(false)
          miniscore=100
          miniscore*=1.2
          ministat=0
          ministat+=opponent.stages[PBStats::ATTACK]
          if ministat>0
            minimini=10*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
            miniscore*=1.2
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            miniscore*=1.3
          end
          if opponent.effects[PBEffects::Attract]>=0
            miniscore*=1.1
          end
          if opponent.status==PBStatuses::PARALYSIS
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Yawn]>0 || opponent.status==PBStatuses::SLEEP
            miniscore*=0.4
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::TANGLEDFEET)
            miniscore*=0.7
          end
          if attacker.pbHasMove?((PBMoves::SUBSTITUTE))
            miniscore*=1.2
            if attacker.effects[PBEffects::Substitute]>0
              miniscore*=1.3
            end
          end
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==3 # Misty
              score*=1.3
              fairyvar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:FAIRY)
                  fairyvar=true
                end
              end
              if !fairyvar
                score*=1.3
              else
                score*=0.6
              end
            end
            if $fefieldeffect==7 # Burning
              firevar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:FIRE)
                  firevar=true
                end
              end
              if !firevar
                score*=1.8
              else
                score*=0.5
              end
            end
            if $fefieldeffect==11 # Corrosive Mist
              poisonvar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:POISON)
                  poisonvar=true
                end
              end
              if !poisonvar
                score*=3
              else
                score*=0.8
              end
            end
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
        end
        invulmove=$pkmn_move[opponent.effects[PBEffects::TwoTurnAttack]][0] #the function code of the current move
        if invulmove==0xC9 || invulmove==0xCC || invulmove==0xCE
          if (pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0)
            score*=2
          end
        end
        if (pbRoughStat(opponent,PBStats::SPEED,skill)>attacker.pbSpeed) ^ (@trickroom!=0)
          score*=1.2 if checkAImoves(PBStuff::TWOTURNAIRMOVE,aimem)
        end
      when 0x16 # Attract
        canattract=true
        agender=attacker.gender
        ogender=opponent.gender
        if agender==2 || ogender==2 || agender==ogender # Pokemon are genderless or same gender
          canattract=false
        elsif opponent.effects[PBEffects::Attract]>=0
          canattract=false
        elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::OBLIVIOUS)
          canattract=false
        elsif pbCheckSideAbility(:AROMAVEIL,opponent)!=nil && !(opponent.moldbroken)
          canattract = false
        end
        if canattract
          score*=1.2
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CUTECHARM)
            score*=0.7
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            score*=1.3
          end
          if opponent.effects[PBEffects::Confusion]>0
            score*=1.1
          end
          if opponent.status==PBStatuses::PARALYSIS
            score*=1.1
          end
          if opponent.effects[PBEffects::Yawn]>0 || opponent.status==PBStatuses::SLEEP
            score*=0.5
          end
          if (oppitemworks && opponent.item == PBItems::DESTINYKNOT)
            score*=0.1
          end
          if attacker.pbHasMove?((PBMoves::SUBSTITUTE))
            score*=1.2
            if attacker.effects[PBEffects::Substitute]>0
              score*=1.3
            end
          end
        else
          score=0
        end
      when 0x17 # Tri Attack
        if opponent.status==0
          miniscore=100
          miniscore*=1.4
          ministat = statchangecounter(opponent,1,7)
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if !opponent.abilitynulled
            miniscore*=0.3 if opponent.ability == PBAbilities::NATURALCURE
            miniscore*=0.7 if opponent.ability == PBAbilities::MARVELSCALE
            miniscore*=0.3 if opponent.ability == PBAbilities::GUTS || opponent.ability == PBAbilities::QUICKFEET
            miniscore*=0.7 if opponent.ability == PBAbilities::SHEDSKIN
            miniscore*=0.5 if opponent.ability == PBAbilities::SYNCHRONIZE && attacker.status==0
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
        end
      when 0x18 # Refresh
        if attacker.status==PBStatuses::BURN || attacker.status==PBStatuses::POISON || attacker.status==PBStatuses::PARALYSIS
          score*=3
        else
          score=0
        end
        if (attacker.hp.to_f)/attacker.totalhp>0.5
          score*=1.5
        else
          score*=0.3
        end
        if opponent.effects[PBEffects::Yawn]>0
          score*=0.1
        end
        score*=0.1 if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
        if opponent.effects[PBEffects::Toxic]>2
          score*=1.3
        end
        score*=1.3 if checkAImoves([PBMoves::HEX],aimem)
      when 0x19 # Aromatherapy
        party=pbParty(attacker.index)
        statuses=0
        for i in 0...party.length
          statuses+=1 if party[i] && party[i].status!=0
        end
        if statuses!=0
          score*=1.2
          statuses=0
          count=-1
          for i in 0...party.length
            count+=1
            next if party[i].nil?
            temproles = pbGetMonRole(party[i],opponent,skill,count,party)
            if party[i].status==PBStatuses::POISON && (party[i].ability == PBAbilities::POISONHEAL)
              score*=0.5
            end
            if (party[i].ability == PBAbilities::GUTS) || (party[i].ability == PBAbilities::QUICKFEET) || party[i].knowsMove?(:FACADE)
              score*=0.8
            end
            if party[i].status==PBStatuses::SLEEP || party[i].status==PBStatuses::FROZEN
              score*=1.1
            end
            if (temproles.include?(PBMonRoles::PHYSICALWALL) || temproles.include?(PBMonRoles::SPECIALWALL)) && party[i].status==PBStatuses::POISON
              score*=1.2
            end
            if temproles.include?(PBMonRoles::SWEEPER) && party[i].status==PBStatuses::PARALYSIS
              score*=1.2
            end
            if party[i].attack>party[i].spatk && party[i].status==PBStatuses::BURN
              score*=1.2
            end
          end
          if attacker.status!=0
            score*=1.3
          end
          if attacker.effects[PBEffects::Toxic]>2
            score*=1.3
          end
          score*=1.1 if checkAIhealing(aimem)
        else
          score=0
        end
      when 0x1A # Safeguard
        if attacker.pbOwnSide.effects[PBEffects::Safeguard]<=0 && ((pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0)) && attacker.status==0 && !roles.include?(PBMonRoles::STATUSABSORBER)
          score+=50 if checkAImoves([PBMoves::SPORE],aimem)
        end
      when 0x1B # Psycho Shift
        if attacker.status!=0 && opponent.effects[PBEffects::Substitute]<=0
          score*=1.3
          if opponent.status==0 && opponent.effects[PBEffects::Yawn]==0
            score*=1.3
            if attacker.status==PBStatuses::BURN && opponent.pbCanBurn?(false)
              if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
                score*=1.2
              end
              if (!opponent.abilitynulled && opponent.ability == PBAbilities::FLAREBOOST)
                score*=0.7
              end
            end
            if attacker.status==PBStatuses::PARALYSIS && opponent.pbCanParalyze?(false)
              if pbRoughStat(opponent,PBStats::ATTACK,skill)<pbRoughStat(opponent,PBStats::SPATK,skill)
                score*=1.1
              end
              if (pbRoughStat(opponent,PBStats::SPEED,skill)>attacker.pbSpeed) ^ (@trickroom!=0)
                score*=1.2
              end
            end
            if attacker.status==PBStatuses::POISON && opponent.pbCanPoison?(false)
              score*=1.1 if checkAIhealing(aimem)
              if attacker.effects[PBEffects::Toxic]>0
                score*=1.4
              end
              if (!opponent.abilitynulled && opponent.ability == PBAbilities::POISONHEAL)
                score*=0.3
              end
              if (!opponent.abilitynulled && opponent.ability == PBAbilities::TOXICBOOST)
                score*=0.7
              end
            end
            if !opponent.abilitynulled && (opponent.ability == PBAbilities::SHEDSKIN || opponent.ability == PBAbilities::NATURALCURE || opponent.ability == PBAbilities::GUTS || opponent.ability == PBAbilities::QUICKFEET || opponent.ability == PBAbilities::MARVELSCALE)
              score*=0.7
            end
            score*=0.7 if checkAImoves([PBMoves::HEX],aimem)
          end
          if attacker.pbHasMove?((PBMoves::HEX))
            score*=1.3
          end
        else
          score=0
        end
      when 0x1C # Howl
        miniscore = setupminiscore(attacker,opponent,skill,move,true,1,false,initialscores,scoreindex)
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.5
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if attacker.status==PBStatuses::BURN || attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        miniscore*=0.3 if checkAImoves([PBMoves::FOULPLAY],aimem)
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken))  && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        if skill>=PBTrainerAI.bestSkill
          if move.id==(PBMoves::MEDITATE)
            if $fefieldeffect==9 # Rainbow
              miniscore*=2
            end
            if $fefieldeffect==20 || $fefieldeffect==37 # Ashen Beach/Psychic Terrain
              miniscore*=3
            end
          end
        end
        if move.basedamage>0
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::ATTACK)
            miniscore=1
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0.5
          end
        else
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::ATTACK)
            miniscore=0
          end
          miniscore*=0 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
            miniscore=1
          end
        end
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        if move.basedamage==0 && $fefieldeffect!=37
          physmove=false
          for j in attacker.moves
            if j.pbIsPhysical?(j.type)
              physmove=true
            end
          end
          score=0 if !physmove
        end
      when 0x1D # Harden
        miniscore = setupminiscore(attacker,opponent,skill,move,false,2,false,initialscores,scoreindex)
        if attacker.stages[PBStats::DEFENSE]>0
          ministat=attacker.stages[PBStats::DEFENSE]
          minimini=-15*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
          miniscore*=1.3
        end
        if skill>=PBTrainerAI.mediumSkill
          miniscore*=0.3 if (checkAIdamage(aimem,attacker,opponent,skill).to_f/attacker.hp)<0.12 && (aimem.length > 0)
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        if move.basedamage>0
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::DEFENSE)
            miniscore=1
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0.5
          end
        else
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::DEFENSE)
            miniscore=0
          end
          miniscore*=0 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
            miniscore=1
          end
        end
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x1E # Defense Curl
        miniscore = setupminiscore(attacker,opponent,skill,move,false,2,false,initialscores,scoreindex)
        if attacker.stages[PBStats::DEFENSE]>0
          ministat=attacker.stages[PBStats::DEFENSE]
          minimini=-15*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
          miniscore*=1.3
        end
        if skill>=PBTrainerAI.mediumSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if (maxdam.to_f/attacker.hp)<0.12 && (aimem.length > 0)
            miniscore*=0.3
          end
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        if move.basedamage>0
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::DEFENSE)
            miniscore=1
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0.5
          end
        else
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::DEFENSE)
            miniscore=0
          end
          miniscore*=0 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
            miniscore=1
          end
        end
        score*=miniscore
        if attacker.pbHasMove?((PBMoves::ROLLOUT)) && attacker.effects[PBEffects::DefenseCurl]==false
          score*=1.3
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x1F # Flame Charge
        miniscore = setupminiscore(attacker,opponent,skill,move,true,16,false,initialscores,scoreindex)
        if attacker.attack<attacker.spatk
          if attacker.stages[PBStats::SPATK]<0
            ministat=attacker.stages[PBStats::SPATK]
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
        else
          if attacker.stages[PBStats::ATTACK]<0
            ministat=attacker.stages[PBStats::ATTACK]
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
        end
        ministat=0
        ministat+=opponent.stages[PBStats::DEFENSE]
        ministat+=opponent.stages[PBStats::SPDEF]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end

        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if @trickroom!=0 || checkAImoves([PBMoves::TRICKROOM],aimem)
          miniscore*=0.2
        end
        if attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.2
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::MOXIE)
          miniscore*=1.3
        end
        if move.basedamage>0
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::SPEED)
            miniscore=1
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0.5
          end
        else
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
            miniscore*=0.6
          end
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::SPEED)
            miniscore=0
          end
          miniscore*=0 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
            miniscore=1
          end
        end
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x20 # Charge Beam
        miniscore = setupminiscore(attacker,opponent,skill,move,true,4,false,initialscores,scoreindex)
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.5
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        if skill>=PBTrainerAI.bestSkill
          if move.id==(PBMoves::CHARGEBEAM)
            if $fefieldeffect==18 # Short Circuit
              miniscore*=1.2
            end
          end
        end
        if move.basedamage>0
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::SPATK)
            miniscore=1
          end
          if miniscore<1
            miniscore = 1
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0.5
          end
        else
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::SPATK)
            miniscore=0
          end
          miniscore*=0 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
            miniscore=1
          end
        end
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        if move.basedamage==0
          specmove=false
          for j in attacker.moves
            if j.pbIsSpecial?(j.type)
              specmove=true
            end
          end
          score=0 if !specmove
        end
      when 0x21 # Charge
        miniscore = setupminiscore(attacker,opponent,skill,move,false,8,false,initialscores,scoreindex)
        if attacker.stages[PBStats::SPDEF]>0
          ministat=attacker.stages[PBStats::SPDEF]
          minimini=-15*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if pbRoughStat(opponent,PBStats::ATTACK,skill)<pbRoughStat(opponent,PBStats::SPATK,skill)
          miniscore*=1.1
        end
        if skill>=PBTrainerAI.mediumSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if (maxdam.to_f/attacker.hp)<0.12 && (aimem.length > 0)
            miniscore*=0.3
          end
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        if move.basedamage>0
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::SPDEF)
            miniscore=1
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0.5
          end
        else
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::SPDEF)
            miniscore=0
          end
          miniscore*=0 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
            miniscore=1
          end
        end
        elecmove=false
        for j in attacker.moves
          if j.type==13 # Move is Electric
            if j.basedamage>0
              elecmove=true
            end
          end
        end
        if elecmove==true && attacker.effects[PBEffects::Charge]==0
          miniscore*=1.5
        end
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x22 # Double Team
        miniscore = setupminiscore(attacker,opponent,skill,move,false,0,false,initialscores,scoreindex)
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD) || checkAIaccuracy(aimem)
          miniscore*=0.2
        end
        if (attitemworks && attacker.item == PBItems::BRIGHTPOWDER) || (attitemworks && attacker.item == PBItems::LAXINCENSE) ||
          ((!attacker.abilitynulled && attacker.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) ||
          ((!attacker.abilitynulled && attacker.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL)
          miniscore*=1.3
        end
        if skill>=PBTrainerAI.bestSkill
          if move.id==(PBMoves::DOUBLETEAM)
            if $fefieldeffect==30 # Mirror Arena
              miniscore*=2
            end
          end
        end
        if move.basedamage>0
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::EVASION)
            miniscore=1
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0.5
          end
        else
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::EVASION)
            miniscore=0
          end
          miniscore*=0 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
            miniscore=1
          end
        end
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x23 # Focus Energy
        if attacker.effects[PBEffects::FocusEnergy]!=2
          if (attacker.hp.to_f)/attacker.totalhp>0.75
            score*=1.2
          end
          if (attacker.hp.to_f)/attacker.totalhp<0.33
            score*=0.3
          end
          if (attacker.hp.to_f)/attacker.totalhp<0.75 && ((!attacker.abilitynulled && attacker.ability == PBAbilities::EMERGENCYEXIT) || (!attacker.abilitynulled && attacker.ability == PBAbilities::WIMPOUT) || (attitemworks && attacker.item == PBItems::EJECTBUTTON))
            score*=0.3
          end
          if attacker.pbOpposingSide.effects[PBEffects::Retaliate]
            score*=0.3
          end
          if opponent.effects[PBEffects::HyperBeam]>0
            score*=1.3
          end
          if opponent.effects[PBEffects::Yawn]>0
            score*=1.7
          end
          score*=1.2 if (attacker.hp/4.0)>checkAIdamage(aimem,attacker,opponent,skill) && (aimem.length > 0)
          if attacker.turncount<2
            score*=1.2
          end
          if opponent.status!=0
            score*=1.2
          end
          if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
            score*=1.3
          end
          if opponent.effects[PBEffects::Encore]>0
            if opponent.moves[(opponent.effects[PBEffects::EncoreIndex])].basedamage==0
              score*=1.5
            end
          end
          if attacker.effects[PBEffects::Confusion]>0
            score*=0.2
          end
          if attacker.effects[PBEffects::LeechSeed]>=0 || attacker.effects[PBEffects::Attract]>=0
            score*=0.6
          end
          score*=0.5 if checkAImoves(PBStuff::SWITCHOUTMOVE,aimem)
          if @doublebattle
            score*=0.5
          end
          if !attacker.abilitynulled && (attacker.ability == PBAbilities::SUPERLUCK || attacker.ability == PBAbilities::SNIPER)
            score*=2
          end
          if attitemworks && (attacker.item == PBItems::SCOPELENS || attacker.item == PBItems::RAZORCLAW || (attacker.item == PBItems::STICK && attacker.species==83) || (attacker.item == PBItems::LUCKYPUNCH && attacker.species==113))
            score*=1.2
          end
          if (attitemworks && attacker.item == PBItems::LANSATBERRY)
            score*=1.3
          end
          if !opponent.abilitynulled && (opponent.ability == PBAbilities::ANGERPOINT || opponent.ability == PBAbilities::SHELLARMOR || opponent.ability == PBAbilities::BATTLEARMOR)
            score*=0.2
          end
          if attacker.pbHasMove?((PBMoves::LASERFOCUS)) || attacker.pbHasMove?((PBMoves::FROSTBREATH)) || attacker.pbHasMove?((PBMoves::STORMTHROW))
            score*=0.5
          end
          for j in attacker.moves
            if j.hasHighCriticalRate?
              score*=2
            end
          end
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==20 # Ashen Beach
              score*=1.5
            end
          end
        else
          score=0
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x24 # Bulk Up
        miniscore = setupminiscore(attacker,opponent,skill,move,true,3,false,initialscores,scoreindex)
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.5
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if attacker.status==PBStatuses::BURN || attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        miniscore*=0.3 if checkAImoves([PBMoves::FOULPLAY],aimem)
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        physmove=false
        for j in attacker.moves
          if j.pbIsPhysical?(j.type)
            physmove=true
          end
        end
        if physmove && !attacker.pbTooHigh?(PBStats::ATTACK)
          miniscore/=100.0
          score*=miniscore
        end
        miniscore=100
        if attacker.effects[PBEffects::Toxic]>0
          miniscore*=0.2
        end
        if pbRoughStat(opponent,PBStats::SPATK,skill)<pbRoughStat(opponent,PBStats::ATTACK,skill)
          if !(roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL))
            if ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && (attacker.hp.to_f)/attacker.totalhp>0.75
              miniscore*=1.3
            elsif (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              miniscore*=0.7
            end
          end
          miniscore*=1.3
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.2
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        if !attacker.pbTooHigh?(PBStats::DEFENSE)
          miniscore/=100.0
          score*=miniscore
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          score=0
        end
        if attacker.pbTooHigh?(PBStats::ATTACK) && attacker.pbTooHigh?(PBStats::DEFENSE)
          score*=0
        end
      when 0x25 # Coil
        miniscore = setupminiscore(attacker,opponent,skill,move,true,5,false,initialscores,scoreindex)
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.3
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.1
        end
        if attacker.status==PBStatuses::BURN || attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        miniscore*=0.3 if checkAImoves([PBMoves::FOULPLAY],aimem)
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        physmove=false
        for j in attacker.moves
          if j.pbIsPhysical?(j.type)
            physmove=true
          end
        end
        if physmove && !attacker.pbTooHigh?(PBStats::ATTACK)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==2 # Grassy Terrain
              miniscore*=2
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        miniscore=100
        if attacker.effects[PBEffects::Toxic]>0
          miniscore*=0.2
        end
        if pbRoughStat(opponent,PBStats::SPATK,skill)<pbRoughStat(opponent,PBStats::ATTACK,skill)
          if !(roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL))
            if ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && (attacker.hp.to_f)/attacker.totalhp>0.75
              miniscore*=1.1
            elsif (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              miniscore*=0.7
            end
          end
          miniscore*=1.1
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.1
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.1
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.2
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.2
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        if !attacker.pbTooHigh?(PBStats::DEFENSE)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==2 # Grassy Terrain
              miniscore*=2
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        miniscore=100
        weakermove=false
        for j in attacker.moves
          if j.basedamage<95
            weakermove=true
          end
        end
        if weakermove
          miniscore*=1.1
        end
        if opponent.stages[PBStats::EVASION]>0
          ministat=opponent.stages[PBStats::EVASION]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER) || (oppitemworks && opponent.item == PBItems::LAXINCENSE) ||
          ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) ||
          ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL)
          miniscore*=1.1
        end
        if !attacker.pbTooHigh?(PBStats::ACCURACY)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==2 # Grassy Terrain
              miniscore*=2
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          score=0
        end
        if attacker.pbTooHigh?(PBStats::ATTACK) && attacker.pbTooHigh?(PBStats::DEFENSE) && attacker.pbTooHigh?(PBStats::ACCURACY)
          score*=0
        end
      when 0x26 # Dragon Dance
        miniscore = setupminiscore(attacker,opponent,skill,move,true,17,false,initialscores,scoreindex)
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        miniscore*=1.2 if checkAIhealing(aimem)
        if (attacker.pbSpeed<=pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          miniscore*=1.3
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if attacker.status==PBStatuses::BURN || attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        miniscore*=0.3 if checkAImoves([PBMoves::FOULPLAY],aimem)
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.3
        end
        physmove=false
        for j in attacker.moves
          if j.pbIsPhysical?(j.type)
            physmove=true
          end
        end
        if physmove && !attacker.pbTooHigh?(PBStats::ATTACK)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==6 || $fefieldeffect==32 # Big Top/Dragon's Den
              miniscore*=2
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        miniscore=100
        if attacker.stages[PBStats::ATTACK]<0
          ministat=attacker.stages[PBStats::ATTACK]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          miniscore*=0.8
        end
        if @trickroom!=0
          miniscore*=0.2
        else
          miniscore*=0.2 if checkAImoves([PBMoves::TRICKROOM],aimem)
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::MOXIE)
          miniscore*=1.3
        end
        if !attacker.pbTooHigh?(PBStats::SPEED)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==6 || $fefieldeffect==32 # Big Top/Dragon's Den
              miniscore*=2
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)

        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          score=0
        end
        if attacker.pbTooHigh?(PBStats::ATTACK) && attacker.pbTooHigh?(PBStats::SPEED)
          score*=0
        end
      when 0x27 # Work Up
        miniscore = setupminiscore(attacker,opponent,skill,move,true,5,false,initialscores,scoreindex)
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.5
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        specmove=false
        for j in attacker.moves
          if j.pbIsSpecial?(j.type)
            specmove=true
          end
        end
        if attacker.status==PBStatuses::BURN && !specmove
          miniscore*=0.5
        end
        if attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        miniscore*=0.3 if checkAImoves([PBMoves::FOULPLAY],aimem)
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        physmove=false
        for j in attacker.moves
          if j.pbIsPhysical?(j.type)
            physmove=true
          end
        end
        if (physmove && !attacker.pbTooHigh?(PBStats::ATTACK)) || (specmove && !attacker.pbTooHigh?(PBStats::SPATK))
          miniscore/=100.0
          score*=miniscore
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          score=0
        end
        if attacker.pbTooHigh?(PBStats::SPATK) && attacker.pbTooHigh?(PBStats::ATTACK)
          score*=0
        end
      when 0x28 # Growth
        miniscore = setupminiscore(attacker,opponent,skill,move,true,5,false,initialscores,scoreindex)
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.5
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        specmove=false
        for j in attacker.moves
          if j.pbIsSpecial?(j.type)
            specmove=true
          end
        end
        if attacker.status==PBStatuses::BURN && !specmove
          miniscore*=0.5
        end
        if attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        miniscore*=0.3 if checkAImoves([PBMoves::FOULPLAY],aimem)
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        physmove=false
        for j in attacker.moves
          if j.pbIsPhysical?(j.type)
            physmove=true
          end
        end
        if (physmove && !attacker.pbTooHigh?(PBStats::ATTACK)) || (specmove && !attacker.pbTooHigh?(PBStats::SPATK))
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==2 || $fefieldeffect==15 || pbWeather==PBWeather::SUNNYDAY # Grassy/Forest
              miniscore*=2
            end
            if ($fefieldeffect==33) # Flower Garden
              if $fecounter>2
                miniscore*=3
              else
                miniscore*=2
              end
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          score=0
        end
        if attacker.pbTooHigh?(PBStats::SPATK) && attacker.pbTooHigh?(PBStats::ATTACK)
          score*=0
        end
      when 0x29 # Hone Claws
        miniscore = setupminiscore(attacker,opponent,skill,move,true,1,false,initialscores,scoreindex)
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore*=1.3 if checkAIhealing(aimem)
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          miniscore*=1.5
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if attacker.status==PBStatuses::BURN || attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        miniscore*=0.3 if checkAImoves([PBMoves::FOULPLAY],aimem)
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        physmove=false
        for j in attacker.moves
          if j.pbIsPhysical?(j.type)
            physmove=true
          end
        end
        if physmove && !attacker.pbTooHigh?(PBStats::ATTACK)
          miniscore/=100.0
          score*=miniscore
        end
        miniscore=100
        weakermove=false
        for j in attacker.moves
          if j.basedamage<95
            weakermove=true
          end
        end
        if weakermove
          miniscore*=1.3
        end
        if opponent.stages[PBStats::EVASION]>0
          ministat=opponent.stages[PBStats::EVASION]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER) || (oppitemworks && opponent.item == PBItems::LAXINCENSE) ||
          ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) ||
          ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL)
          miniscore*=1.3
        end
        if !attacker.pbTooHigh?(PBStats::ACCURACY)
          miniscore/=100.0
          score*=miniscore
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          score=0
        end
        if attacker.pbTooHigh?(PBStats::ACCURACY) && attacker.pbTooHigh?(PBStats::ATTACK)
          score*=0
        end
      when 0x2A # Cosmic Power
        miniscore = setupminiscore(attacker,opponent,skill,move,false,10,false,initialscores,scoreindex)
        if attacker.stages[PBStats::SPDEF]>0 || attacker.stages[PBStats::DEFENSE]>0
          ministat=attacker.stages[PBStats::SPDEF]
          ministat+=attacker.stages[PBStats::DEFENSE]
          minimini=-5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if skill>=PBTrainerAI.mediumSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if (maxdam.to_f/attacker.hp)<0.12 && (aimem.length > 0)
            miniscore*=0.3
          end
        end
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.5
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.7
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        if !attacker.pbTooHigh?(PBStats::SPDEF) || !attacker.pbTooHigh?(PBStats::DEFENSE)
          if skill>=PBTrainerAI.bestSkill
            if move.id==(PBMoves::COSMICPOWER)
              if $fefieldeffect==29 || $fefieldeffect==34 || $fefieldeffect==35 # Holy/Starlight Arena/New World
                miniscore*=2
              end
            end
            if move.id==(PBMoves::DEFENDORDER)
              if $fefieldeffect==15 # Forest
                miniscore*=2
              end
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          score=0
        end
        if attacker.pbTooHigh?(PBStats::SPDEF) && attacker.pbTooHigh?(PBStats::DEFENSE)
          score*=0
        end
      when 0x2B # Quiver Dance
        miniscore = setupminiscore(attacker,opponent,skill,move,true,28,false,initialscores,scoreindex)
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.5
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        specmove=false
        for j in attacker.moves
          if j.pbIsSpecial?(j.type)
            specmove=true
          end
        end
        if specmove && !attacker.pbTooHigh?(PBStats::SPATK)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==6 # Big Top
              miniscore*=2
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        miniscore=100
        if attacker.effects[PBEffects::Toxic]>0
          miniscore*=0.2
        end
        if pbRoughStat(opponent,PBStats::SPATK,skill)>pbRoughStat(opponent,PBStats::ATTACK,skill)
          if !(roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL))
            if ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && (attacker.hp.to_f)/attacker.totalhp>0.75
              miniscore*=1.3
            elsif (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              miniscore*=0.7
            end
          end
          miniscore*=1.3
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        if !attacker.pbTooHigh?(PBStats::SPDEF)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==6 # Big Top
              miniscore*=2
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        miniscore=100
        if attacker.stages[PBStats::SPATK]<0
          ministat=attacker.stages[PBStats::SPATK]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          miniscore*=0.8
        end
        if @trickroom!=0
          miniscore*=0.2
        else
          miniscore*=0.2 if checkAImoves([PBMoves::TRICKROOM],aimem)
        end
        if !attacker.pbTooHigh?(PBStats::SPEED)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==6 # Big Top
              miniscore*=2
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          score=0
        end
        if attacker.pbTooHigh?(PBStats::SPATK) && attacker.pbTooHigh?(PBStats::SPDEF) && attacker.pbTooHigh?(PBStats::SPEED)
          score*=0
        end
      when 0x2C # Calm Mind
        miniscore = setupminiscore(attacker,opponent,skill,move,true,12,false,initialscores,scoreindex)
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.5
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        specmove=false
        for j in attacker.moves
          if j.pbIsSpecial?(j.type)
            specmove=true
          end
        end
        if specmove && !attacker.pbTooHigh?(PBStats::SPATK)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==5 || $fefieldeffect==20 || $fefieldeffect==37 # Chess/Ashen Beach/Psychic Terrain
              miniscore*=2
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        miniscore=100
        if attacker.effects[PBEffects::Toxic]>0
          miniscore*=0.2
        end
        if pbRoughStat(opponent,PBStats::SPATK,skill)>pbRoughStat(opponent,PBStats::ATTACK,skill)
          if !(roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL))
            if ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && (attacker.hp.to_f)/attacker.totalhp>0.75
              miniscore*=1.3
            elsif (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              miniscore*=0.7
            end
          end
          miniscore*=1.3
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        if !attacker.pbTooHigh?(PBStats::SPDEF)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==5 || $fefieldeffect==20 || $fefieldeffect==37 # Chess/Ashen Beach/Psychic Terrain
              miniscore*=2
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          score=0
        end
        if attacker.pbTooHigh?(PBStats::SPATK) && attacker.pbTooHigh?(PBStats::SPDEF)
          score*=0
        end
      when 0x2D # Ancient power
        miniscore=100
        miniscore*=2
        if score == 110
          miniscore *= 1.3
        end
        if (attacker.hp.to_f)/attacker.totalhp>0.75
          miniscore*=1.1
        end
        if opponent.effects[PBEffects::HyperBeam]>0
          miniscore*=1.2
        end
        if opponent.effects[PBEffects::Yawn]>0
          miniscore*=1.3
        end
        if skill>=PBTrainerAI.mediumSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if maxdam<(attacker.hp/3.0) && (aimem.length > 0)
            miniscore*=1.1
          else
            if move.basedamage==0
              miniscore*=0.8
              if maxdam>attacker.hp
                miniscore*=0.1
              end
            end
          end
        end
        if attacker.turncount<2
          miniscore*=1.1
        end
        if opponent.status!=0
          miniscore*=1.1
        end
        if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
          miniscore*=1.3
        end
        if opponent.effects[PBEffects::Encore]>0
          if opponent.moves[(opponent.effects[PBEffects::EncoreIndex])].basedamage==0
            miniscore*=1.3
          end
        end
        miniscore*=0.2 if checkAImoves(PBStuff::SWITCHOUTMOVE,aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SIMPLE)
          miniscore*=2
        end
        if @doublebattle
          miniscore*=0.3
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        miniscore-=100
        if move.addlEffect.to_f != 100
          miniscore*=(move.addlEffect.to_f/100)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
            miniscore*=2
          end
        end
        miniscore+=100
        miniscore/=100.0
        if attacker.pbTooHigh?(PBStats::ATTACK) && attacker.pbTooHigh?(PBStats::DEFENSE) && attacker.pbTooHigh?(PBStats::SPATK) && attacker.pbTooHigh?(PBStats::SPDEF) && attacker.pbTooHigh?(PBStats::SPEED)
          miniscore=0
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        miniscore*=0 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score *= 0.9
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=0.9
        end
        if miniscore > 1
          score*=miniscore
        end
      when 0x2E # Swords Dance
        miniscore = setupminiscore(attacker,opponent,skill,move,true,1,true,initialscores,scoreindex)
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.5
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.2
        end
        if attacker.status==PBStatuses::BURN || attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        miniscore*=0.2 if checkAImoves([PBMoves::FOULPLAY],aimem)
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.5
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        if skill>=PBTrainerAI.bestSkill
          if move.id==(PBMoves::SWORDSDANCE)
            if $fefieldeffect==6 || $fefieldeffect==31  # Big Top/Fairy Tale
              miniscore*=1.5
            end
          end
        end
        miniscore/=100.0
        if attacker.pbTooHigh?(PBStats::ATTACK)
          miniscore=0
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          miniscore*=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=1
        end
        physmove=false
        for j in attacker.moves
          if j.pbIsPhysical?(j.type)
            physmove=true
          end
        end
        miniscore=0 if !physmove
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x2F # Iron Defense
        miniscore = setupminiscore(attacker,opponent,skill,move,false,2,true,initialscores,scoreindex)
        if attacker.stages[PBStats::DEFENSE]>0
          ministat=attacker.stages[PBStats::DEFENSE]
          minimini=-15*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
          miniscore*=1.3
        end
        if skill>=PBTrainerAI.mediumSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if (maxdam.to_f/attacker.hp)<0.12 && (aimem.length > 0)
            miniscore*=0.3
          end
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        if skill>=PBTrainerAI.bestSkill
          if move.id==(PBMoves::IRONDEFENSE)
            if $fefieldeffect==17 # Factory
              miniscore*=1.5
            end
          end
          if move.id==(PBMoves::DIAMONDSTORM)
            if $fefieldeffect==23 # Cave
              miniscore*=1.5
            end
          end
        end
        if move.basedamage>0
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::DEFENSE)
            miniscore=1
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0.5
          end
        else
          miniscore/=100.0
          if attacker.pbTooHigh?(PBStats::DEFENSE)
            miniscore=0
          end
          miniscore*=0 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            miniscore*=0
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
            miniscore*=1
          end
        end
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x30 # Agility
        miniscore = setupminiscore(attacker,opponent,skill,move,true,16,true,initialscores,scoreindex)
        if attacker.attack<attacker.spatk
          if attacker.stages[PBStats::SPATK]<0
            ministat=attacker.stages[PBStats::SPATK]
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
        else
          if attacker.stages[PBStats::ATTACK]<0
            ministat=attacker.stages[PBStats::ATTACK]
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
        end
        ministat=0
        ministat+=opponent.stages[PBStats::DEFENSE]
        ministat+=opponent.stages[PBStats::SPDEF]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          miniscore*=0.3
          livecount=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount+=1 if i.hp!=0
          end
          if livecount==1
              miniscore*=0.1
          end
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if @trickroom!=0
          miniscore*=0.2
        else
          miniscore*=0.2 if checkAImoves([PBMoves::TRICKROOM],aimem)
        end
        if attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.2
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::MOXIE)
          miniscore*=1.3
        end
        if skill>=PBTrainerAI.bestSkill
          if move.id==(PBMoves::ROCKPOLISH)
            if $fefieldeffect==14 # Rocky Field
              miniscore*=1.5
            end
            if $fefieldeffect==25 # Crystal Cavern
              miniscore*=2
            end
          end
        end
        miniscore/=100.0
        if attacker.pbTooHigh?(PBStats::SPEED)
          miniscore=0
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          miniscore*=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=1
        end
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x31 # Autotomize
        miniscore = setupminiscore(attacker,opponent,skill,move,true,16,true,initialscores,scoreindex)
        if attacker.attack<attacker.spatk
          if attacker.stages[PBStats::SPATK]<0
            ministat=attacker.stages[PBStats::SPATK]
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
        else
          if attacker.stages[PBStats::ATTACK]<0
            ministat=attacker.stages[PBStats::ATTACK]
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
        end
        ministat=0
        ministat+=opponent.stages[PBStats::DEFENSE]
        ministat+=opponent.stages[PBStats::SPDEF]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          miniscore*=0.3
          livecount=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount+=1 if i.hp!=0
          end
          if livecount==1
              miniscore*=0.1
          end
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if @trickroom!=0
          miniscore*=0.2
        else
          miniscore*=0.2 if checkAImoves([PBMoves::TRICKROOM],aimem)
        end
        if attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.2
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::MOXIE)
          miniscore*=1.3
        end
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==17 # Factory
            miniscore*=1.5
          end
        end
        miniscore*=1.5 if checkAImoves([PBMoves::LOWKICK,PBMoves::GRASSKNOT],aimem)
        miniscore*=0.5 if checkAImoves([PBMoves::HEATCRASH,PBMoves::HEAVYSLAM],aimem)
        if attacker.pbHasMove?((PBMoves::HEATCRASH)) || attacker.pbHasMove?((PBMoves::HEAVYSLAM))
          miniscore*=0.8
        end
        miniscore/=100.0
        if attacker.pbTooHigh?(PBStats::SPEED)
          miniscore=0
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          miniscore*=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=1
        end
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x32 # Nasty Plot
        miniscore = setupminiscore(attacker,opponent,skill,move,true,4,true,initialscores,scoreindex)
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.5
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==5 || $fefieldeffect==37 # Chess/Psychic Terrain
            miniscore*=1.5
          end
        end
        miniscore/=100.0
        if attacker.pbTooHigh?(PBStats::SPATK)
          miniscore=0
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          miniscore*=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=1
        end
        specmove=false
        for j in attacker.moves
          if j.pbIsSpecial?(j.type)
            specmove=true
          end
        end
        miniscore=0 if !specmove
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x33 # Amnesia
        miniscore = setupminiscore(attacker,opponent,skill,move,false,0,true,initialscores,scoreindex)
        if attacker.stages[PBStats::SPDEF]>0
          ministat=attacker.stages[PBStats::SPDEF]
          minimini=-15*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if pbRoughStat(opponent,PBStats::ATTACK,skill)<pbRoughStat(opponent,PBStats::SPATK,skill)
          miniscore*=1.3
        end
        if skill>=PBTrainerAI.mediumSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if (maxdam.to_f/attacker.hp)<0.12 && (aimem.length > 0)
            miniscore*=0.3
          end
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        miniscore/=100.0
        if attacker.pbTooHigh?(PBStats::SPDEF)
          miniscore=0
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          miniscore*=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=1
        end
        score*=miniscore
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==25 # Glitch
            score *= 2
          end
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x34 # Minimize
        miniscore = setupminiscore(attacker,opponent,skill,move,false,0,true,initialscores,scoreindex)
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD) || checkAIaccuracy(aimem)
          miniscore*=0.2
        end
        if (attitemworks && (attacker.item == PBItems::BRIGHTPOWDER || attacker.item == PBItems::LAXINCENSE)) ||
          ((!attacker.abilitynulled && attacker.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) ||
          ((!attacker.abilitynulled && attacker.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL)
          miniscore*=1.3
        end
        miniscore/=100.0
        if attacker.pbTooHigh?(PBStats::EVASION)
          miniscore=0
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          miniscore*=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=1
        end
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x35 # Shell Smash
        miniscore = setupminiscore(attacker,opponent,skill,move,true,21,true,initialscores,scoreindex)
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed<=pbRoughStat(opponent,PBStats::SPEED,skill) && (2*attacker.pbSpeed)>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.3
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.5
        end
        specmove=false
        for j in attacker.moves
          if j.pbIsSpecial?(j.type)
            specmove=true
          end
        end
        if attacker.status==PBStatuses::BURN && !specmove
          miniscore*=0.5
        end
        if attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.5
        end
        miniscore*=0.2 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        if (attitemworks && attacker.item == PBItems::WHITEHERB)
          miniscore *= 1.5
        else
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            miniscore*=0.1
          end
        end
        if @trickroom!=0
          miniscore*=0.2
        else
          miniscore*=0.2 if checkAImoves([PBMoves::TRICKROOM],aimem)
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::MOXIE)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::WHITEHERB)
          miniscore*=1.5
        end
        if !attacker.pbTooHigh?(PBStats::SPEED)
          miniscore/=100.0
          score*=miniscore
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY) && !healmove
          score=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          score=0
        end
      when 0x36 # Shift Gear
        miniscore = setupminiscore(attacker,opponent,skill,move,true,17,false,initialscores,scoreindex)
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        miniscore*=1.3 if checkAIhealing(aimem)
        if (attacker.pbSpeed<=pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          miniscore*=1.3
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.5
        end
        if attacker.status==PBStatuses::BURN || attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        miniscore*=0.3 if checkAImoves([PBMoves::FOULPLAY],aimem)
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        physmove=false
        for j in attacker.moves
          if j.pbIsPhysical?(j.type)
            physmove=true
          end
        end
        if physmove && !attacker.pbTooHigh?(PBStats::ATTACK)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==17 # Factory Field
              miniscore*=1.5
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        miniscore=100
        if attacker.stages[PBStats::ATTACK]<0
          ministat=attacker.stages[PBStats::ATTACK]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          miniscore*=0.8
        end
        if @trickroom!=0 || checkAImoves([PBMoves::TRICKROOM],aimem)
          miniscore*=0.1
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::MOXIE)
          miniscore*=1.3
        end
        if !attacker.pbTooHigh?(PBStats::SPEED)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==17 # Factory Field
              miniscore*=1.5
            end
          end
          miniscore/=100.0
          score*=miniscore
        end
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          score = 0
        end
      when 0x37 # Acupressure
        miniscore = setupminiscore(attacker,opponent,skill,move,false,0,false,initialscores,scoreindex)
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD) || checkAIaccuracy(aimem)
          miniscore*=0.2
        end
        if (attitemworks && attacker.item == PBItems::BRIGHTPOWDER) || (attitemworks && attacker.item == PBItems::LAXINCENSE) ||
          ((!attacker.abilitynulled && attacker.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) ||
          ((!attacker.abilitynulled && attacker.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL)
          miniscore*=1.3
        end
        miniscore/=100.0
        maxstat=0
        maxstat+=1 if attacker.pbTooHigh?(PBStats::ATTACK)
        maxstat+=1 if attacker.pbTooHigh?(PBStats::DEFENSE)
        maxstat+=1 if attacker.pbTooHigh?(PBStats::SPATK)
        maxstat+=1 if attacker.pbTooHigh?(PBStats::SPDEF)
        maxstat+=1 if attacker.pbTooHigh?(PBStats::SPEED)
        maxstat+=1 if attacker.pbTooHigh?(PBStats::ACCURACY)
        maxstat+=1 if attacker.pbTooHigh?(PBStats::EVASION)
        if maxstat>1
          miniscore=0
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          miniscore*=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=1
        end
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x38 # Cotton Guard
        miniscore = setupminiscore(attacker,opponent,skill,move,false,2,true,initialscores,scoreindex)
        if attacker.stages[PBStats::DEFENSE]>0
          ministat=attacker.stages[PBStats::DEFENSE]
          minimini=-15*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
          miniscore*=1.3
        end
        if skill>=PBTrainerAI.mediumSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if (maxdam.to_f/attacker.hp)<0.12 && (aimem.length > 0)
            miniscore*=0.3
          end
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        miniscore/=100.0
        if attacker.pbTooHigh?(PBStats::DEFENSE)
          miniscore=0
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          miniscore*=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=1
        end
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x39 # Tail Glow
        miniscore = setupminiscore(attacker,opponent,skill,move,true,4,true,initialscores,scoreindex)
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.5
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          miniscore*=1.4
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        miniscore/=100.0
        if attacker.pbTooHigh?(PBStats::SPATK)
          miniscore=0
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          miniscore*=0
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=1
        end
        specmove=false
        for j in attacker.moves
          if j.pbIsSpecial?(j.type)
            specmove=true
          end
        end
        miniscore=0 if !specmove
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x3A # Belly Drum
        miniscore=100
        if attacker.effects[PBEffects::Substitute]>0 || attacker.effects[PBEffects::Disguise]
          miniscore*=1.5
        end
        if initialscores.length>0
          miniscore*=1.3 if hasbadmoves(initialscores,scoreindex,20)
        end
        if (attacker.hp.to_f)/attacker.totalhp>0.85
          miniscore*=1.2
        end
        if opponent.effects[PBEffects::HyperBeam]>0
          miniscore*=1.5
        end
        if opponent.effects[PBEffects::Yawn]>0
          miniscore*=1.7
        end
        if skill>=PBTrainerAI.mediumSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if maxdam<(attacker.hp/4.0) && (aimem.length > 0)
            miniscore*=1.4
          else
            if move.basedamage==0
              miniscore*=0.8
              if maxdam>attacker.hp
                miniscore*=0.1
              end
            end
          end
        else
          if move.basedamage==0
            effcheck = PBTypes.getCombinedEffectiveness(opponent.type1,attacker.type1,attacker.type2)
            if effcheck > 4
              miniscore*=0.5
            end
            effcheck2 = PBTypes.getCombinedEffectiveness(opponent.type2,attacker.type1,attacker.type2)
            if effcheck2 > 4
              miniscore*=0.5
            end
          end
        end
        if attacker.turncount<1
          miniscore*=1.2
        end
        if opponent.status!=0
          miniscore*=1.2
        end
        if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
          miniscore*=1.4
        end
        if opponent.effects[PBEffects::Encore]>0
          if opponent.moves[(opponent.effects[PBEffects::EncoreIndex])].basedamage==0
            miniscore*=1.5
          end
        end
        if attacker.effects[PBEffects::Confusion]>0
          miniscore*=0.1
        end
        if attacker.effects[PBEffects::LeechSeed]>=0 || attacker.effects[PBEffects::Attract]>=0
          miniscore*=0.2
        end
        miniscore*=0.1 if checkAImoves(PBStuff::SWITCHOUTMOVE,aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=0
        end
        if @doublebattle
          miniscore*=0.1
        end
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=10*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-10)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.5
        else
          primove=false
          for j in attacker.moves
            if j.priority>0
              primove=true
            end
          end
          if !primove
            miniscore*=0.3
          end
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if attacker.status==PBStatuses::BURN
          miniscore*=0.8
        end
        if attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.2
        end
        miniscore*=0.1 if checkAImoves([PBMoves::FOULPLAY],aimem)
        miniscore*=0.1 if checkAIpriority(aimem)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
          miniscore*=0.6
        end
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==6  # Big Top
            miniscore*=1.5
          end
        end
        miniscore/=100.0
        if attacker.pbTooHigh?(PBStats::ATTACK)
          miniscore=0
        end
        score*=0.3 if checkAImoves([PBMoves::CLEARSMOG,PBMoves::HAZE],aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          miniscore*=0
        end
        physmove=false
        for j in attacker.moves
          if j.pbIsPhysical?(j.type)
            physmove=true
          end
        end
        miniscore=0 if !physmove
        score*=miniscore
        if (opponent.level-5)>attacker.level
          score*=0.6
          if (opponent.level-10)>attacker.level
            score*=0.2
          end
        end
      when 0x3B # Superpower
        thisinitial = score
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score*=1.7
        else
          if thisinitial<100
            score*=0.9
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=1.2
            else
              score*=0.5 if checkAIhealing(aimem)
            end
          end
          if initialscores.length>0
            score*=0.7 if hasgreatmoves(initialscores,scoreindex,skill)
          end
          miniscore=100
          livecount=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount+=1 if i.hp!=0
          end
          if livecount>1
            miniscore*=(livecount-3)
            miniscore/=100.0
            miniscore*=0.05
            miniscore=(1-miniscore)
            score*=miniscore
          end
          count=-1
          party=pbParty(attacker.index)
          pivotvar=false
          for i in 0...party.length
            count+=1
            next if party[i].nil?
            temproles = pbGetMonRole(party[i],opponent,skill,count,party)
            if temproles.include?(PBMonRoles::PIVOT)
              pivotvar=true
            end
          end
          if pivotvar && !@doublebattle
            score*=1.2
          end
          livecount2=0
          for i in pbParty(attacker.index)
            next if i.nil?
            livecount2+=1 if i.hp!=0
          end
          if livecount>1 && livecount2==1
            score*=0.8
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::MOXIE)
            score*=1.5
          end
        end
      when 0x3C # Close Combat
        thisinitial = score
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score*=1.5
        else
          if thisinitial<100
            score*=0.9
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=1.3
            else
              score*=0.7 if checkAIpriority(aimem)
            end
            score*=0.7 if checkAIhealing(aimem)
          end
          if initialscores.length>0
            score*=0.7 if hasgreatmoves(initialscores,scoreindex,skill)
          end
          miniscore=100
          livecount=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount+=1 if i.hp!=0
          end
          if livecount>1
            miniscore*=(livecount-3)
            miniscore/=100.0
            miniscore*=0.05
            miniscore=(1-miniscore)
            score*=miniscore
          end
          count=-1
          party=pbParty(attacker.index)
          pivotvar=false
          for i in 0...party.length
            count+=1
            next if party[i].nil?
            temproles = pbGetMonRole(party[i],opponent,skill,count,party)
            if temproles.include?(PBMonRoles::PIVOT)
              pivotvar=true
            end
          end
          if pivotvar && !@doublebattle
            score*=1.2
          end
          livecount2=0
          for i in pbParty(attacker.index)
            next if i.nil?
            livecount2+=1 if i.hp!=0
          end
          if livecount>1 && livecount2==1
            score*=0.9
          end
        end
      when 0x3D # V-Create
        thisinitial = score
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score*=1.7
        else
          if thisinitial<100
            score*=0.8
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=1.3
            else
              livecount=0
              for i in pbParty(opponent.index)
                next if i.nil?
                livecount+=1 if i.hp!=0
              end
              livecount2=0
              for i in pbParty(attacker.index)
                next if i.nil?
                livecount2+=1 if i.hp!=0
              end
              if livecount>1 && livecount2==1
                score*=0.7
              end
              score*=0.7 if checkAIpriority(aimem)
            end
          end
          if initialscores.length>0
            score*=0.7 if hasgreatmoves(initialscores,scoreindex,skill)
          end
          miniscore=100
          livecount=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount+=1 if i.hp!=0
          end
          if livecount>1
            miniscore*=(livecount-3)
            miniscore/=100.0
            miniscore*=0.05
            miniscore=(1-miniscore)
            score*=miniscore
          end
          count=-1
          party=pbParty(attacker.index)
          pivotvar=false
          for i in 0...party.length
            count+=1
            next if party[i].nil?
            temproles = pbGetMonRole(party[i],opponent,skill,count,party)
            if temproles.include?(PBMonRoles::PIVOT)
              pivotvar=true
            end
          end
          if pivotvar && !@doublebattle
            score*=1.2
          end
        end
      when 0x3E # Hammer Arm
        thisinitial = score
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score*=1.3
        else
          if thisinitial<100
            score*=0.9
          end
          if initialscores.length>0
            score*=0.7 if hasgreatmoves(initialscores,scoreindex,skill)
          end
          livecount=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount+=1 if i.hp!=0
          end
          livecount2=0
          for i in pbParty(attacker.index)
            next if i.nil?
            livecount2+=1 if i.hp!=0
          end
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=0.8
            if livecount>1 && livecount2==1
              score*=0.8
            end
          else
            score*=1.1
          end
          if roles.include?(PBMonRoles::TANK)
            score*=1.1
          end
          miniscore=100
          livecount=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount+=1 if i.hp!=0
          end
          if livecount>1
            miniscore*=(livecount-3)
            miniscore/=100.0
            miniscore*=0.05
            miniscore=(1-miniscore)
            score*=miniscore
          end
          count=-1
          party=pbParty(attacker.index)
          pivotvar=false
          for i in 0...party.length
            count+=1
            next if party[i].nil?
            temproles = pbGetMonRole(party[i],opponent,skill,count,party)
            if temproles.include?(PBMonRoles::PIVOT)
              pivotvar=true
            end
          end
          if pivotvar && !@doublebattle
            score*=1.2
          end
        end
      when 0x3F # Overheat
        thisinitial = score
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score*=1.7
        else
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==24 # Glitch
              if attacker.spdef>attacker.spatk
                score*=1.4
              end
            end
          end
          if thisinitial<100
            score*=0.9
            score*=0.5 if checkAIhealing(aimem)
          end
          if initialscores.length>0
            score*=0.7 if hasgreatmoves(initialscores,scoreindex,skill)
          end
          miniscore=100
          livecount=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount+=1 if i.hp!=0
          end
          if livecount>1
            miniscore*=(livecount-1)
            miniscore/=100.0
            miniscore*=0.05
            miniscore=(1-miniscore)
            score*=miniscore
          end
          count=-1
          party=pbParty(attacker.index)
          pivotvar=false
          for i in 0...party.length
            count+=1
            next if party[i].nil?
            temproles = pbGetMonRole(party[i],opponent,skill,count,party)
            if temproles.include?(PBMonRoles::PIVOT)
              pivotvar=true
            end
          end
          if pivotvar && !@doublebattle
            score*=1.2
          end
          livecount2=0
          for i in pbParty(attacker.index)
            next if i.nil?
            livecount2+=1 if i.hp!=0
          end
          if livecount>1 && livecount2==1
            score*=0.8
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::SOULHEART)
            score*=1.3
          end
        end
      when 0x40 # Flatter
        if opponent != attacker.pbPartner
          if opponent.pbCanConfuse?(false)
            miniscore=100
            ministat=0
            ministat+=opponent.stages[PBStats::ATTACK]
            if ministat>0
              minimini=10*ministat
              minimini+=100
              minimini/=100.0
              miniscore*=minimini
            end
            if opponent.attack>opponent.spatk
              miniscore*=1.5
            else
              miniscore*=0.3
            end
            if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
              miniscore*=1.3
            end
            if opponent.effects[PBEffects::Attract]>=0
              miniscore*=1.1
            end
            if opponent.status==PBStatuses::PARALYSIS
              miniscore*=1.1
            end
            if opponent.effects[PBEffects::Yawn]>0 || opponent.status==PBStatuses::SLEEP
              miniscore*=0.4
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::TANGLEDFEET)
              miniscore*=0.7
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::CONTRARY)
              miniscore*=1.5
            end
            if attacker.pbHasMove?((PBMoves::SUBSTITUTE))
              miniscore*=1.2
              if attacker.effects[PBEffects::Substitute]>0
                miniscore*=1.3
              end
            end
            miniscore/=100.0
            score*=miniscore
          else
            score=0
          end
        else
          if opponent.pbCanConfuse?(false)
            score*=0.5
          else
            score*=1.5
          end
          if opponent.attack<opponent.spatk
            score*=1.5
          end
          if (1.0/opponent.totalhp)*opponent.hp < 0.6
            score*=0.3
          end
          if opponent.effects[PBEffects::Attract]>=0 || opponent.status==PBStatuses::PARALYSIS || opponent.effects[PBEffects::Yawn]>0 || opponent.status==PBStatuses::SLEEP
            score*=0.3
          end
          if oppitemworks && (opponent.item == PBItems::PERSIMBERRY || opponent.item == PBItems::LUMBERRY)
            score*=1.2
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::CONTRARY)
            score*=0
          end
          if opponent.effects[PBEffects::Substitute]>0
            score*=0
          end
          opp1 = attacker.pbOppositeOpposing
          opp2 = opp1.pbPartner
          if opponent.pbSpeed > opp1.pbSpeed && opponent.pbSpeed > opp2.pbSpeed
            score*=1.3
          else
            score*=0.7
          end
        end
      when 0x41 # Swagger
        if opponent != attacker.pbPartner
          if opponent.pbCanConfuse?(false)
            miniscore=100
            if opponent.attack<opponent.spatk
              miniscore*=1.5
            else
              miniscore*=0.7
            end
            if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
              miniscore*=1.3
            end
            if opponent.effects[PBEffects::Attract]>=0
              miniscore*=1.3
            end
            if opponent.status==PBStatuses::PARALYSIS
              miniscore*=1.3
            end
            if opponent.effects[PBEffects::Yawn]>0 || opponent.status==PBStatuses::SLEEP
              miniscore*=0.4
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::TANGLEDFEET)
              miniscore*=0.7
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::CONTRARY)
              miniscore*=1.5
            end
            if attacker.pbHasMove?((PBMoves::SUBSTITUTE))
              miniscore*=1.2
              if attacker.effects[PBEffects::Substitute]>0
                miniscore*=1.3
              end
            end
            if attacker.pbHasMove?((PBMoves::FOULPLAY))
              miniscore*=1.5
            end
            miniscore/=100.0
            score*=miniscore
          else
            score=0
          end
        else
          if opponent.pbCanConfuse?(false)
            score*=0.5
          else
            score*=1.5
          end
          if opponent.attack>opponent.spatk
            score*=1.5
          end
          if (1.0/opponent.totalhp)*opponent.hp < 0.6
            score*=0.3
          end
          if opponent.effects[PBEffects::Attract]>=0 || opponent.status==PBStatuses::PARALYSIS || opponent.effects[PBEffects::Yawn]>0 || opponent.status==PBStatuses::SLEEP
            score*=0.3
          end
          if (oppitemworks && opponent.item == PBItems::PERSIMBERRY) || (oppitemworks && opponent.item == PBItems::LUMBERRY)
            score*=1.2
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::CONTRARY)
            score*=0
          end
          if opponent.effects[PBEffects::Substitute]>0
            score*=0
          end
          opp1 = attacker.pbOppositeOpposing
          opp2 = opp1.pbPartner
          if opponent.pbSpeed > opp1.pbSpeed && opponent.pbSpeed > opp2.pbSpeed
            score*=1.3
          else
            score*=0.7
          end
          if opp1.pbHasMove?((PBMoves::FOULPLAY)) || opp2.pbHasMove?((PBMoves::FOULPLAY))
            score*=0.3
          end
        end
      when 0x42 # Growl
        if (pbRoughStat(opponent,PBStats::SPATK,skill)>pbRoughStat(opponent,PBStats::ATTACK,skill)) || opponent.stages[PBStats::ATTACK]>0 || !opponent.pbCanReduceStatStage?(PBStats::ATTACK)
          if move.basedamage==0
            score=0
          end
        else
          miniscore=100
          if skill>=PBTrainerAI.bestSkill
            if move.id==(PBMoves::LUNGE)
              if $fefieldeffect==13 # Icy Field
                miniscore*=1.5
              end
            end
            if move.id==(PBMoves::AURORABEAM)
              if $fefieldeffect==30 # Mirror Field
                if (attacker.stages[PBStats::ACCURACY] < 0 || opponent.stages[PBStats::EVASION] > 0 ||
                  (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER) || (oppitemworks && opponent.item == PBItems::LAXINCENSE) ||
                  ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) ||
                  ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL) ||
                  opponent.vanished) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD) && !(!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD)
                  miniscore*=2
                end
              end
            end
          end
          miniscore *= unsetupminiscore(attacker,opponent,skill,move,roles,1,true)
          miniscore/=100.0
          score*=miniscore
        end
      when 0x43 # Tail Whip
        physmove=false
        for j in attacker.moves
          if j.pbIsPhysical?(j.type)
            physmove=true
          end
        end
        if !physmove || opponent.stages[PBStats::DEFENSE]>0 || !opponent.pbCanReduceStatStage?(PBStats::DEFENSE)
          if move.basedamage==0
            score=0
          end
        else
          score*=unsetupminiscore(attacker,opponent,skill,move,roles,2,true)
        end
      when 0x44 # Rock Tomb / Bulldoze / Glaciate 
        if ((pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0)) || opponent.stages[PBStats::SPEED]>0 || !opponent.pbCanReduceStatStage?(PBStats::SPEED)
          if move.basedamage==0
            score=0
          end
        else
          miniscore=100
          if opponent.stages[PBStats::SPEED]<0
            minimini = 5*opponent.stages[PBStats::SPEED]
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if skill>=PBTrainerAI.bestSkill
            if move.id==(PBMoves::GLACIATE)
              if $fefieldeffect==26 # Murkwater Surface
                poisonvar=false
                watervar=false
                icevar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:POISON)
                    poisonvar=true
                  end
                  if mon.hasType?(:WATER)
                    watervar=true
                  end
                  if mon.hasType?(:ICE)
                    icevar=true
                  end
                end
                if !poisonvar && !watervar
                  miniscore*=1.3
                end
                if icevar
                  miniscore*=1.5
                end
              end
              if $fefieldeffect==21 # Water Surface
                watervar=false
                icevar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:WATER)
                    watervar=true
                  end
                  if mon.hasType?(:ICE)
                    icevar=true
                  end
                end
                if !watervar
                  miniscore*=1.3
                end
                if icevar
                  miniscore*=1.5
                end
              end
              if $fefieldeffect==32 # Dragon's Den
                dragonvar=false
                rockvar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:DRAGON)
                    dragonvar=true
                  end
                  if mon.hasType?(:ROCK)
                    rockvar=true
                  end
                end
                if !dragonvar
                  miniscore*=1.3
                end
                if rockvar
                  miniscore*=1.3
                end
              end
              if $fefieldeffect==16 # Superheated
                firevar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:FIRE)
                    firevar=true
                  end
                end
                if !firevar
                  miniscore*=1.5
                end
              end
            end
            if move.id==(PBMoves::BULLDOZE)
              if $fefieldeffect==4 # Dark Crystal Cavern
                darkvar=false
                rockvar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:DARK)
                    darkvar=true
                  end
                  if mon.hasType?(:ROCK)
                    rockvar=true
                  end
                end
                if !darkvar
                  miniscore*=1.3
                end
                if rockvar
                  miniscore*=1.2
                end
              end
              if $fefieldeffect==25 # Crystal Cavern
                dragonvar=false
                rockvar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:DRAGON)
                    dragonvar=true
                  end
                  if mon.hasType?(:ROCK)
                    rockvar=true
                  end
                end
                if !dragonvar
                  miniscore*=1.3
                end
                if rockvar
                  miniscore*=1.2
                end
              end
              if $fefieldeffect==13 # Icy Field
                icevar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:ICE)
                    icevar=true
                  end
                end
                if !icevar
                  miniscore*=1.5
                end
              end
              if $fefieldeffect==17 # Factory
                miniscore*=1.2
                darkvar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:DARK)
                    darkvar=true
                  end
                end
                if darkvar
                  miniscore*=1.3
                end
              end
              if $fefieldeffect==23 # Cave
                if !(!attacker.abilitynulled && attacker.ability == PBAbilities::ROCKHEAD) && !(!attacker.abilitynulled && attacker.ability == PBAbilities::BULLETPROOF)
                  miniscore*=0.7
                  if $fecounter >=1
                    miniscore *= 0.3
                  end
                end
              end
              if $fefieldeffect==30 # Mirror Arena
                if opponent.stages[PBStats::EVASION] > 0 ||
                  (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER) || (oppitemworks && opponent.item == PBItems::LAXINCENSE) ||
                  ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) ||
                  ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL)
                  miniscore*=1.3
                else
                  miniscore*=0.5
                end
              end
            end
          end
          greatmoves = hasgreatmoves(initialscores,scoreindex,skill)
          miniscore*=unsetupminiscore(attacker,opponent,skill,move,roles,3,false,greatmoves)
          miniscore/=100.0
          score*=miniscore
        end
      when 0x45 # Snarl
        if (pbRoughStat(opponent,PBStats::SPATK,skill)<pbRoughStat(opponent,PBStats::ATTACK,skill)) || opponent.stages[PBStats::SPATK]>0 || !opponent.pbCanReduceStatStage?(PBStats::SPATK)
          if move.basedamage==0
            score=0
          end
        else
          score*=unsetupminiscore(attacker,opponent,skill,move,roles,1,false)
        end
      when 0x46 # Psychic
        specmove=false
        for j in attacker.moves
          if j.pbIsSpecial?(j.type)
            specmove=true
          end
        end
        if !specmove || opponent.stages[PBStats::SPDEF]>0 || !opponent.pbCanReduceStatStage?(PBStats::SPDEF)
          if move.basedamage==0
            score=0
          end
        else
          miniscore=100
          if opponent.stages[PBStats::SPDEF]<0
            minimini = 5*opponent.stages[PBStats::SPDEF]
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if skill>=PBTrainerAI.bestSkill
            if move.id==(PBMoves::FLASHCANNON) || move.id==(PBMoves::LUSTERPURGE)
              if $fefieldeffect==30 # Mirror Arena
                if (attacker.stages[PBStats::ACCURACY] < 0 || opponent.stages[PBStats::EVASION] > 0 ||
                  (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER) || (oppitemworks && opponent.item == PBItems::LAXINCENSE) ||
                  ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) ||
                  ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL) ||
                  opponent.vanished) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD) && !(!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD)
                  miniscore*=2
                end
              end
            end
          end
          miniscore*= unsetupminiscore(attacker,opponent,skill,move,roles,2,false)
          miniscore/=100.0
          score*=miniscore
        end
      when 0x47 # Sand Attack
        if checkAIaccuracy(aimem) || opponent.stages[PBStats::ACCURACY]>0 || !opponent.pbCanReduceStatStage?(PBStats::ACCURACY)
          if move.basedamage==0
            score=0
          end
        else
          miniscore=100
          if opponent.stages[PBStats::ACCURACY]<0
            minimini = 5*opponent.stages[PBStats::ACCURACY]
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if skill>=PBTrainerAI.bestSkill
            if move.id==(PBMoves::KINESIS)
              if $fefieldeffect==20 # Ashen Beach
                miniscore*=1.3
              end
              if $fefieldeffect==37 # Psychic Terrain
                miniscore*=1.6
              end
            end
            if move.id==(PBMoves::SANDATTACK)
              if $fefieldeffect==20 || $fefieldeffect==12 # Ashen Beach/Desert
                miniscore*=1.3
              end
            end
            if move.id==(PBMoves::MIRRORSHOT)
              if $fefieldeffect==30 # Mirror Arena
                if (attacker.stages[PBStats::ACCURACY] < 0 || opponent.stages[PBStats::EVASION] > 0 ||
                  (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER) || (oppitemworks && opponent.item == PBItems::LAXINCENSE) ||
                  ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) ||
                  ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL) ||
                  opponent.vanished) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD) && !(!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD)
                  miniscore*=2
                end
              end
            end
            if move.id==(PBMoves::MUDDYWATER)
              if $fefieldeffect==7 # Burning
                firevar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:FIRE)
                    firevar=true
                  end
                end
                if firevar
                  miniscore*=0
                else
                  miniscore*=2
                end
              end
              if $fefieldeffect==16 # Superheated
                miniscore*=0.7
              end
              if $fefieldeffect==32 # Dragon's Den
                firevar=false
                dragonvar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:FIRE)
                    firevar=true
                  end
                  if mon.hasType?(:DRAGON)
                    dragonvar=true
                  end
                end
                if firevar || dragonvar
                  miniscore*=0
                else
                  miniscore*=1.5
                end
              end
            end
            if move.id==(PBMoves::NIGHTDAZE)
              if $fefieldeffect==25 # Crystal Cavern
                darkvar=false
                dragonvar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:DARK)
                    darkvar=true
                  end
                  if mon.hasType?(:DRAGON)
                    dragonvar=true
                  end
                end
                if darkvar
                  miniscore*=2
                end
                if dragonvar
                  miniscore*=0.75
                end
              end
            end
            if move.id==(PBMoves::LEAFTORNADO)
              if $fefieldeffect==20 # Ahsen Beach
                miniscore*=0.7
              end
            end
            if move.id==(PBMoves::FLASH)
              if $fefieldeffect==4 || $fefieldeffect==18 || $fefieldeffect==30 || $fefieldeffect==34 || $fefieldeffect==35 # Dark Crystal Cavern/Short-Circuit/Mirror/Starlight/New World
                miniscore*=1.3
              end
            end
            if move.id==(PBMoves::SMOKESCREEN)
              if $fefieldeffect==7 || $fefieldeffect==11 # Burning/Corrosive Mist
                miniscore*=1.3
              end
            end
          end
          miniscore*= unsetupminiscore(attacker,opponent,skill,move,roles,1,false)
          miniscore/=100.0
          score*=miniscore
        end
      when 0x48 # Sweet Scent
        score=0 #no
      when 0x49 # Defog
        miniscore=100
        livecount1=0
        for i in pbParty(attacker.index)
          next if i.nil?
          livecount1+=1 if i.hp!=0
        end
        livecount2=0
        for i in pbParty(opponent.index)
          next if i.nil?
          livecount2+=1 if i.hp!=0
        end
        if livecount1>1
          miniscore*=2 if attacker.pbOwnSide.effects[PBEffects::StealthRock]
          miniscore*=3 if attacker.pbOwnSide.effects[PBEffects::StickyWeb]
          miniscore*=(1.5**attacker.pbOwnSide.effects[PBEffects::Spikes])
          miniscore*=(1.7**attacker.pbOwnSide.effects[PBEffects::ToxicSpikes])
        end
        miniscore-=100
        miniscore*=(livecount1-1) if livecount1>1
        minimini=100
        if livecount2>1
          minimini*=0.5 if attacker.pbOwnSide.effects[PBEffects::StealthRock]
          minimini*=0.3 if attacker.pbOwnSide.effects[PBEffects::StickyWeb]
          minimini*=(0.7**attacker.pbOwnSide.effects[PBEffects::Spikes])
          minimini*=(0.6**attacker.pbOwnSide.effects[PBEffects::ToxicSpikes])
        end
        minimini-=100
        minimini*=(livecount2-1) if livecount2>1
        miniscore+=minimini
        miniscore+=100
        if miniscore<0
          miniscore=0
        end
        miniscore/=100.0
        score*=miniscore
        if opponent.pbOwnSide.effects[PBEffects::Reflect]>0
          score*=2
        end
        if opponent.pbOwnSide.effects[PBEffects::LightScreen]>0
          score*=2
        end
        if opponent.pbOwnSide.effects[PBEffects::Safeguard]>0
          score*=1.3
        end
        if opponent.pbOwnSide.effects[PBEffects::AuroraVeil]>0
          score*=3
        end
        if opponent.pbOwnSide.effects[PBEffects::Mist]>0
          score*=1.3
        end
      when 0x4A # Tickle
        miniscore=100
        if (pbRoughStat(opponent,PBStats::SPATK,skill)>pbRoughStat(opponent,PBStats::ATTACK,skill)) || opponent.stages[PBStats::ATTACK]>0 || !opponent.pbCanReduceStatStage?(PBStats::ATTACK)
          if move.basedamage==0
            miniscore*=0.5
          end
        else
          if opponent.stages[PBStats::ATTACK]+opponent.stages[PBStats::DEFENSE]<0
            minimini = 5*opponent.stages[PBStats::ATTACK]
            minimini+= 5*opponent.stages[PBStats::DEFENSE]
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          miniscore*= unsetupminiscore(attacker,opponent,skill,move,roles,1,true)
        end
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        physmove=false
        for j in attacker.moves
          if j.pbIsPhysical?(j.type)
            physmove=true
          end
        end
        if !physmove || opponent.stages[PBStats::DEFENSE]>0 || !opponent.pbCanReduceStatStage?(PBStats::DEFENSE)
          if move.basedamage==0
            miniscore*=0.5
          end
        else
          miniscore*= unsetupminiscore(attacker,opponent,skill,move,roles,2,true)
        end
        miniscore/=100.0
        score*=miniscore
      when 0x4B # Feather Dance
        if (pbRoughStat(opponent,PBStats::SPATK,skill)>pbRoughStat(opponent,PBStats::ATTACK,skill)) || opponent.stages[PBStats::ATTACK]>1 || !opponent.pbCanReduceStatStage?(PBStats::ATTACK)
          if move.basedamage==0
            score=0
          end
        else
          miniscore=100
          if opponent.stages[PBStats::ATTACK]<0
            minimini = 5*opponent.stages[PBStats::ATTACK]
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==6 # Big Top
              miniscore*=1.5
            end
          end
          miniscore*= unsetupminiscore(attacker,opponent,skill,move,roles,1,true)
          miniscore/=100.0
          score*=miniscore
        end
      when 0x4C # Screech
        physmove=false
        for j in attacker.moves
          if j.pbIsPhysical?(j.type)
            physmove=true
          end
        end
        if !physmove || opponent.stages[PBStats::DEFENSE]>1 || !opponent.pbCanReduceStatStage?(PBStats::DEFENSE)
          if move.basedamage==0
            score=0
          end
        else
          if opponent.stages[PBStats::DEFENSE]<0
            minimini = 5*opponent.stages[PBStats::DEFENSE]
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          miniscore*= unsetupminiscore(attacker,opponent,skill,move,roles,2,true)
          miniscore/=100.0
          score*=miniscore
        end
      when 0x4D # Scary Face
        if ((pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0)) || opponent.stages[PBStats::SPEED]>1 || !opponent.pbCanReduceStatStage?(PBStats::SPEED)
          if move.basedamage==0
            score=0
          end
        else
          miniscore=100
          if opponent.stages[PBStats::SPEED]<0
            minimini = 5*opponent.stages[PBStats::SPEED]
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          greatmoves = hasgreatmoves(initialscores,scoreindex,skill)
          miniscore*=unsetupminiscore(attacker,opponent,skill,move,roles,3,false,greatmoves)
          miniscore/=100.0
          score*=miniscore
        end
      when 0x4E # Captivate
        canattract=true
        agender=attacker.gender
        ogender=opponent.gender
        if agender==2 || ogender==2 || agender==ogender # Pokemon are genderless or same gender
          canattract=false
        elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::OBLIVIOUS)
          canattract=false
        end
        if (pbRoughStat(opponent,PBStats::SPATK,skill)<pbRoughStat(opponent,PBStats::ATTACK,skill)) || opponent.stages[PBStats::SPATK]>1 || !opponent.pbCanReduceStatStage?(PBStats::SPATK)
          if move.basedamage==0
            score=0
          end
        elsif !canattract
          score=0
        else
          miniscore=100
          if opponent.stages[PBStats::SPATK]<0
            minimini = 5*opponent.stages[PBStats::SPATK]
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          miniscore*= unsetupminiscore(attacker,opponent,skill,move,roles,1,false)
          miniscore/=100.0
          score*=miniscore
        end
      when 0x4F # Acid Spray
        specmove=false
        for j in attacker.moves
          if j.pbIsSpecial?(j.type)
            specmove=true
          end
        end
        if !specmove || opponent.stages[PBStats::SPDEF]>1 || !opponent.pbCanReduceStatStage?(PBStats::SPDEF)
          if move.basedamage==0
            score=0
          end
        else
          miniscore=100
          if skill>=PBTrainerAI.bestSkill
            if move.id==(PBMoves::METALSOUND)
              if $fefieldeffect==17 || $fefieldeffect==18 # Factory/Short-Circuit
                miniscore*=1.5
              end
            end
            if move.id==(PBMoves::SEEDFLARE)
              if $fefieldeffect==10 # Corrosive
                poisonvar=false
                grassvar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:POISON)
                    poisonvar=true
                  end
                  if mon.hasType?(:GRASS)
                    grassvar=true
                  end
                end
                if !poisonvar
                  miniscore*=1.5
                end
                if grassvar
                  miniscore*=1.5
                end
              end
            end
          end
          miniscore*= unsetupminiscore(attacker,opponent,skill,move,roles,2,false)
          miniscore/=100.0
          score*=miniscore
        end
      when 0x50 # Clear Smog
        if opponent.effects[PBEffects::Substitute]<=0
          miniscore = 5*statchangecounter(opponent,1,7)
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
            score*=1.1
          end
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==3 # Misty
              poisonvar=false
              fairyvar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:POISON)
                  poisonvar=true
                end
                if mon.hasType?(:FAIRY)
                  fairyvar=true
                end
              end
              if poisonvar
                score*=1.3
              end
              if !fairyvar
                score*=1.3
              end
            end
          end
        end
      when 0x51 # Haze
        miniscore = (-10)* statchangecounter(attacker,1,7)
        minimini = (10)* statchangecounter(opponent,1,7)
        if @doublebattle
          if attacker.pbPartner.hp>0
            miniscore+= (-10)* statchangecounter(attacker.pbPartner,1,7)
          end
          if opponent.pbPartner.hp>0
            minimini+= (10)* statchangecounter(opponent.pbPartner,1,7)
          end
        end
        if miniscore==0 && minimini==0
          score*=0
        else
          miniscore+=minimini
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST) || checkAImoves(PBStuff::SETUPMOVE,aimem)
          score*=0.8
        end
      when 0x52 # Power Swap
        stages=0
        stages+=attacker.stages[PBStats::ATTACK]
        stages+=attacker.stages[PBStats::SPATK]
        miniscore = (-10)*stages
        if attacker.attack > attacker.spatk
          if attacker.stages[PBStats::ATTACK]!=0
            miniscore*=2
          end
        else
          if attacker.stages[PBStats::SPATK]!=0
            miniscore*=2
          end
        end
        stages=0
        stages+=opponent.stages[PBStats::ATTACK]
        stages+=opponent.stages[PBStats::SPATK]
        minimini = (10)*stages
        if opponent.attack > opponent.spatk
          if opponent.stages[PBStats::ATTACK]!=0
            minimini*=2
          end
        else
          if opponent.stages[PBStats::SPATK]!=0
            minimini*=2
          end
        end
        if miniscore==0 && minimini==0
          score*=0
        else
          miniscore+=minimini
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
          if @doublebattle
            score*=0.8
          end
        end
      when 0x53 # Guard Swap
        stages=0
        stages+=attacker.stages[PBStats::DEFENSE]
        stages+=attacker.stages[PBStats::SPDEF]
        miniscore = (-10)*stages
        if attacker.defense > attacker.spdef
          if attacker.stages[PBStats::DEFENSE]!=0
            miniscore*=2
          end
        else
          if attacker.stages[PBStats::SPDEF]!=0
            miniscore*=2
          end
        end
        stages=0
        stages+=opponent.stages[PBStats::DEFENSE]
        stages+=opponent.stages[PBStats::SPDEF]
        minimini = (10)*stages
        if opponent.defense > opponent.spdef
          if opponent.stages[PBStats::DEFENSE]!=0
            minimini*=2
          end
        else
          if opponent.stages[PBStats::SPDEF]!=0
            minimini*=2
          end
        end
        if miniscore==0 && minimini==0
          score*=0
        else
          miniscore+=minimini
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
          if @doublebattle
            score*=0.8
          end
        end
      when 0x54 # Heart Swap
        stages=0
        stages+=attacker.stages[PBStats::ATTACK] unless attacker.attack<attacker.spatk
        stages+=attacker.stages[PBStats::DEFENSE] unless opponent.attack<opponent.spatk
        stages+=attacker.stages[PBStats::SPEED]
        stages+=attacker.stages[PBStats::SPATK] unless attacker.attack>attacker.spatk
        stages+=attacker.stages[PBStats::SPDEF] unless opponent.attack>opponent.spatk
        stages+=attacker.stages[PBStats::EVASION]
        stages+=attacker.stages[PBStats::ACCURACY]
        miniscore = (-10)*stages
        stages=0
        stages+=opponent.stages[PBStats::ATTACK] unless opponent.attack<opponent.spatk
        stages+=opponent.stages[PBStats::DEFENSE] unless attacker.attack<attacker.spatk
        stages+=opponent.stages[PBStats::SPEED]
        stages+=opponent.stages[PBStats::SPATK] unless opponent.attack>opponent.spatk
        stages+=opponent.stages[PBStats::SPDEF] unless attacker.attack>attacker.spatk
        stages+=opponent.stages[PBStats::EVASION]
        stages+=opponent.stages[PBStats::ACCURACY]
        minimini = (10)*stages
        if !(miniscore==0 && minimini==0)
          miniscore+=minimini
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
          if @doublebattle
            score*=0.8
          end
        else
          if $fefieldeffect==35 # New World
            score=25
          else
            score=0
          end
        end
        if $fefieldeffect==35 # New World
          ministat = opponent.hp + attacker.hp*0.5
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if maxdam>ministat
            score*=0.5
          else
            if maxdam>attacker.hp
              if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
                score*=2
              else
                score*=0*5
              end
            else
              miniscore = opponent.hp * (1.0/attacker.hp)
              score*=miniscore
            end
          end
        end
      when 0x55 # Psych Up
        stages=0
        stages+=attacker.stages[PBStats::ATTACK] unless attacker.attack<attacker.spatk
        stages+=attacker.stages[PBStats::DEFENSE] unless opponent.attack<opponent.spatk
        stages+=attacker.stages[PBStats::SPEED]
        stages+=attacker.stages[PBStats::SPATK] unless attacker.attack>attacker.spatk
        stages+=attacker.stages[PBStats::SPDEF] unless opponent.attack>opponent.spatk
        stages+=attacker.stages[PBStats::EVASION]
        stages+=attacker.stages[PBStats::ACCURACY]
        miniscore = (-10)*stages
        stages=0
        stages+=opponent.stages[PBStats::ATTACK] unless attacker.attack<attacker.spatk
        stages+=opponent.stages[PBStats::DEFENSE] unless opponent.attack<opponent.spatk
        stages+=opponent.stages[PBStats::SPEED]
        stages+=opponent.stages[PBStats::SPATK] unless attacker.attack>attacker.spatk
        stages+=opponent.stages[PBStats::SPDEF] unless opponent.attack>opponent.spatk
        stages+=opponent.stages[PBStats::EVASION]
        stages+=opponent.stages[PBStats::ACCURACY]
        minimini = (10)*stages
        if !(miniscore==0 && minimini==0)
          miniscore+=minimini
          miniscore+=100
          miniscore/=100
          score*=miniscore
        else
          if $fefieldeffect==37 # Psychic Terrain
            score=35
          else
            score=0
          end
        end
        if $fefieldeffect==37 # Psychic Terrain
          miniscore=100
          if initialscores.length>0
            miniscore*=1.3 if hasbadmoves(initialscores,scoreindex,20)
          end
          if attacker.hp*(1.0/attacker.totalhp)>=0.75
            miniscore*=1.2
          end
          if opponent.effects[PBEffects::HyperBeam]>0
            miniscore*=1.3
          end
          if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
            miniscore*=1.3
          end
          if opponent.effects[PBEffects::Encore]>0
            if opponent.moves[(opponent.effects[PBEffects::EncoreIndex])].basedamage==0
              miniscore*=1.5
            end
          end
          if attacker.effects[PBEffects::Confusion]>0
            miniscore*=0.5
          end
          if attacker.effects[PBEffects::LeechSeed]>=0 || attacker.effects[PBEffects::Attract]>=0
            miniscore*=0.5
          end
          if skill>=PBTrainerAI.bestSkill
            miniscore*=1.3 if checkAIhealing(aimem)
            miniscore*=0.6 if checkAIpriority(aimem)
          end
          if roles.include?(PBMonRoles::SWEEPER)
            miniscore*=1.3
          end
          specialvar = false
          for i in attacker.moves
            if i.pbIsSpecial?(i.type)
              special=true
            end
          end
          if attacker.stages[PBStats::SPATK]!=6 && specialvar
            score*=miniscore
          else
            score=0
          end
        end
      when 0x56 # Mist
        miniscore = 1
        minimini = 1
        if attacker.pbOwnSide.effects[PBEffects::Mist]==0
          minimini*=1.1
          movecheck=false
          # check opponent for stat decreasing moves
          if aimem.length > 0
            for j in aimem
              movecheck=true if (j.function==0x42 || j.function==0x43 || j.function==0x44 || j.function==0x45 || j.function==0x46 || j.function==0x47 || j.function==0x48 || j.function==0x49 || j.function==0x4A || j.function==0x4B || j.function==0x4C || j.function==0x4D || j.function==0x4E || j.function==0x4F || j.function==0xE2 || j.function==0x138 || j.function==0x13B || j.function==0x13F)
            end
          end
          if movecheck
            minimini*=1.3
          end
        end
        if $fefieldeffect!=3 && $fefieldeffect!=22 && $fefieldeffect!=35# (not) Misty Terrain
          miniscore*=getFieldDisruptScore(attacker,opponent,skill)
          fairyvar=false
          for mon in pbParty(attacker.index)
            next if mon.nil?
            if mon.hasType?(:FAIRY)
              fairyvar=true
            end
          end
          if fairyvar
            miniscore*=1.3
          end
          if opponent.pbHasType?(:DRAGON) && !attacker.pbHasType?(:FAIRY)
            miniscore*=1.3
          end
          if attacker.pbHasType?(:DRAGON)
            miniscore*=0.5
          end
          if opponent.pbHasType?(:FAIRY)
            miniscore*=0.5
          end
          if attacker.pbHasType?(:FAIRY) && opponent.spatk>opponent.attack
            miniscore*=1.5
          end
          if (attitemworks && attacker.item == PBItems::AMPLIFIELDROCK)
            miniscore*=2
          end
        end
        score*=miniscore
        score*=minimini
        if miniscore<=1 && minimini<=1
          score*=0
        end
      when 0x57 # Power Trick
        if attacker.attack - attacker.defense >= 100
          if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) || (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom!=0)
            score*=1.5
          end
          if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
            score*=2
          end
          healmove=false
          for j in attacker.moves
            if j.isHealingMove?
              healmove=true
            end
          end
          if healmove
            score*=2
          end
        elsif attacker.defense - attacker.attack >= 100
          if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) || (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom!=0)
            score*=1.5
            if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
              score*=2
            end
          else
            score*=0
          end
        else
          score*=0.1
        end
        if attacker.effects[PBEffects::PowerTrick]
          score*=0.1
        end
      when 0x58 # Power Split
        if  pbRoughStat(opponent,PBStats::ATTACK,skill)> pbRoughStat(opponent,PBStats::SPATK,skill)
          if attacker.attack > pbRoughStat(opponent,PBStats::ATTACK,skill)
            score*=0
          else
            miniscore = pbRoughStat(opponent,PBStats::ATTACK,skill) - attacker.attack
            miniscore+=100
            miniscore/=100
            if attacker.attack>attacker.spatk
              miniscore*=2
            else
              miniscore*=0.5
            end
            score*=miniscore
          end
        else
          if attacker.spatk > pbRoughStat(opponent,PBStats::SPATK,skill)
            score*=0
          else
            miniscore = pbRoughStat(opponent,PBStats::SPATK,skill) - attacker.spatk
            miniscore+=100
            miniscore/=100
            if attacker.attack<attacker.spatk
              miniscore*=2
            else
              miniscore*=0.5
            end
            score*=miniscore
          end
        end
      when 0x59 # Guard Split
        if  pbRoughStat(opponent,PBStats::ATTACK,skill)> pbRoughStat(opponent,PBStats::SPATK,skill)
          if attacker.defense > pbRoughStat(opponent,PBStats::DEFENSE,skill)
            score*=0
          else
            miniscore = pbRoughStat(opponent,PBStats::DEFENSE,skill) - attacker.defense
            miniscore+=100
            miniscore/=100
            if attacker.attack>attacker.spatk
              miniscore*=2
            else
              miniscore*=0.5
            end
            score*=miniscore
          end
        else
          if attacker.spdef > pbRoughStat(opponent,PBStats::SPDEF,skill)
            score*=0
          else
            miniscore = pbRoughStat(opponent,PBStats::SPDEF,skill) - attacker.spdef
            miniscore+=100
            miniscore/=100
            if attacker.attack<attacker.spatk
              miniscore*=2
            else
              miniscore*=0.5
            end
            score*=miniscore
          end
        end
      when 0x5A # Pain Split
        if opponent.effects[PBEffects::Substitute]<=0
          ministat = opponent.hp + (attacker.hp/2.0)
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if maxdam>ministat
            score*=0
          elsif maxdam>attacker.hp
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=2
            else
              score*=0
            end
          else
            miniscore=(opponent.hp/(attacker.hp).to_f)
            score*=miniscore
          end
        else
          score*=0
        end
      when 0x5B # Tailwind
        if attacker.pbOwnSide.effects[PBEffects::Tailwind]>0
          score = 0
        else
          score*=1.5
          if ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && !roles.include?(PBMonRoles::LEAD)
            score*=0.9
            livecount=0
            for i in pbParty(attacker.index)
              next if i.nil?
              livecount+=1 if i.hp!=0
            end
            if livecount==1
                score*=0.4
            end
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
            score*=0.5
          end
          score*=0.1 if @trickroom!=0 || checkAImoves([PBMoves::TRICKROOM],aimem)
          if roles.include?(PBMonRoles::LEAD)
            score*=1.4
          end
          if @opponent.is_a?(Array) == false
            if @opponent.trainertype==PBTrainers::ADRIENN
              score *= 2.5
            end
          end
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==3 # Misty
              fairyvar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:FAIRY)
                  fairyvar=true
                end
              end
              if !fairyvar
                score*=1.5
              end
              if !@opponent.is_a?(Array)
                if @opponent.trainertype==PBTrainers::ADRIENN
                  score*=2
                end
              end
            end
            if $fefieldeffect==7 # Burning
              firevar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:FIRE)
                  firevar=true
                end
                if !firevar
                  score*=1.2
                end
              end
            end
            if $fefieldeffect==11 # Corromist
              poisonvar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:POISON)
                  poisonvar=true
                end
                if !poisonvar
                  score*=1.2
                end
              end
            end
            if $fefieldeffect==27 || $fefieldeffect==28 # Mountain/Snowy Mountain
              score*=1.5
              for mon in pbParty(attacker.index)
                flyingvar=false
                next if mon.nil?
                if mon.hasType?(:FLYING)
                  flyingvar=true
                end
                if flyingvar
                  score*=1.5
                end
              end
            end
          end
        end
      when 0x5C # Mimic
        blacklist=[
          0x02,   # Struggle
          0x14,   # Chatter
          0x5C,   # Mimic
          0x5D,   # Sketch
          0xB6    # Metronome
        ]
        miniscore = $pkmn_move[opponent.lastMoveUsed][1]
        if miniscore=0
          miniscore=40
        end
        miniscore+=100
        miniscore/=100.0
        if miniscore<=1.5
          miniscore*=0.5
        end
        score*=miniscore
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          if blacklist.include?($pkmn_move[opponent.lastMoveUsed][1]) || opponent.lastMoveUsed<0
            score*=0
          end
        else
          score*=0.5
        end
        if opponent.effects[PBEffects::Substitute] > 0
          score*=0
        end
      when 0x5D # Sketch
        blacklist=[
          0x02,   # Struggle
          0x14,   # Chatter
          0x5D,   # Sketch
        ]
        miniscore = $pkmn_move[opponent.lastMoveUsedSketch][1]
        if miniscore=0
          miniscore=40
        end
        miniscore+=100
        miniscore/=100.0
        if miniscore<=1.5
          miniscore*=0.5
        end
        score*=miniscore
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          if blacklist.include?($pkmn_move[opponent.lastMoveUsedSketch][0]) || opponent.lastMoveUsedSketch<0
            score*=0
          end
        else
          score*=0.5
        end
        if opponent.effects[PBEffects::Substitute]>0
          score*= 0
        end
      when 0x5E # Conversion
        miniscore = [PBTypes.getCombinedEffectiveness(opponent.type1,attacker.type1,attacker.type2),PBTypes.getCombinedEffectiveness(opponent.type2,attacker.type1,attacker.type2)].max
        minimini = [PBTypes.getEffectiveness(opponent.type1,attacker.moves[0].type),PBTypes.getEffectiveness(opponent.type2,attacker.moves[0].type)].max
        if minimini < miniscore
          score*=3
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.2
          else
            score*=0.5
          end
          stabvar = false
          for i in attacker.moves
            if i.type==attacker.type1 || i.type==attacker.type2
              stabvar = true
            end
          end
          if !stabvar
            score*=1.3
          end
          if $feconversionuse==1
            score*=0.3
          end
        else
          score*=0
        end
        if $fefieldeffect!=24 && $fefieldeffect!=22 && $fefieldeffect!=35
          miniscore = getFieldDisruptScore(attacker,opponent,skill)
          if $feconversionuse!=2
            miniscore-=1
            miniscore/=2.0
            miniscore+=1
          end
          score*=miniscore
        end
        if (attacker.moves[0].type == attacker.type1 && attacker.moves[0].type == attacker.type2)
          score = 0
        end
      when 0x5F # Conversion 2
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=1.2
        else
          score*=0.7
        end
        stabvar = false
        for i in attacker.moves
          if i.type==attacker.type1 || i.type==attacker.type2
            stabvar = true
          end
        end
        if stabvar
          score*=1.3
        else
          score*=0.7
        end
        if $feconversionuse==2
          score*=0.3
        end
        if $fefieldeffect!=24 && $fefieldeffect!=22 && $fefieldeffect!=35
          miniscore = getFieldDisruptScore(attacker,opponent,skill)
          if $feconversionuse!=1
            miniscore-=1
            miniscore/=2.0
            miniscore+=1
          end
          score*=miniscore
        end
      when 0x60 # Camouflage
        type = 0
        case $fefieldeffect
          when 25
            type = PBTypes::QMARKS #type is random
          when 35
            type = PBTypes::QMARKS
          else
            camotypes = FieldEffects::MIMICRY
            type = camotypes[$fefieldeffect]
        end
        miniscore = [PBTypes.getCombinedEffectiveness(opponent.type1,attacker.type1,attacker.type2),PBTypes.getCombinedEffectiveness(opponent.type2,attacker.type1,attacker.type2)].max
        minimini = [PBTypes.getEffectiveness(opponent.type1,type),PBTypes.getEffectiveness(opponent.type2,type)].max
        if minimini < miniscore
          score*=2
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.2
          else
            score*=0.7
          end
          stabvar = false
          for i in attacker.moves
            if i.type==attacker.type1 || i.type==attacker.type2
              stabvar = true
            end
          end
          if !stabvar
            score*=1.2
          else
            score*=0.6
          end
        else
          score*=0
        end
      when 0x61 # Soak
        sevar = false
        for i in attacker.moves
          if (i.type == PBTypes::ELECTRIC) || (i.type == PBTypes::GRASS)
            sevar = true
          end
        end
        if sevar
          score*=1.5
        else
          score*=0.7
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          if attacker.pbHasMove?((PBMoves::TOXIC))
            if attacker.pbHasType?(:STEEL) || attacker.pbHasType?(:POISON)
              score*=1.5
            end
          end
        end
        if aimem.length > 0
          movecheck=false
          for j in aimem
            movecheck=true if (j.type == PBTypes::WATER)
          end
          if movecheck
            score*=0.5
          else
            score*=1.1
          end
        end
        if opponent.type1==(PBTypes::WATER) && opponent.type1==(PBTypes::WATER)
          score=0
        end
      when 0x62 # Reflect Type
        typeid=getID(PBTypes,type)
        miniscore = [PBTypes.getCombinedEffectiveness(opponent.type1,attacker.type1,attacker.type2),PBTypes.getCombinedEffectiveness(opponent.type2,attacker.type1,attacker.type2)].max
        minimini = [PBTypes.getCombinedEffectiveness(opponent.type1,opponent.type1,opponent.type2),PBTypes.getCombinedEffectiveness(opponent.type2,opponent.type1,opponent.type2)].max
        if minimini < miniscore
          score*=3
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.2
          else
            score*=0.7
          end
          stabvar = false
          oppstab = false
          for i in attacker.moves
            if i.type == attacker.type1 || i.type == attacker.type2
              stabvar = true
            end
            if i.type == opponent.type1 || i.type == opponent.type2
              oppstab = true
            end
          end
          if !stabvar
            score*=1.2
          end
          if oppstab
            score*=1.3
          end
        else
          score*=0
        end
        if (attacker.ability == PBAbilities::MULTITYPE) || (attacker.type1 == opponent.type1 && attacker.type2 == opponent.type2) || (attacker.type1 == opponent.type2 && attacker.type2 == opponent.type1)
          score*=0
        end
      when 0x63 # Simple Beam
        if !(opponent.ability == PBAbilities::SIMPLE) && !(PBStuff::FIXEDABILITIES).include?(opponent.ability)
          miniscore = getAbilityDisruptScore(move,attacker,opponent,skill)
          if opponent == attacker.pbPartner
            if miniscore < 2
              miniscore = 2 - miniscore
            else
              miniscore = 0
            end
          end
          score*=miniscore
          if checkAImoves(PBStuff::SETUPMOVE,aimem)
            if opponent==attacker.pbPartner
              score*=1.3
            else
              score*=0.5
            end
          end
        else
          score*=0
        end
      when 0x64 # Worry Seed
        if !(opponent.ability == PBAbilities::INSOMNIA)  && opponent.effects[PBEffects::Substitute]<=0 && !(PBStuff::FIXEDABILITIES).include?(opponent.ability)
          miniscore = getAbilityDisruptScore(move,attacker,opponent,skill)
          score*=miniscore
          if checkAImoves([PBMoves::SNORE,PBMoves::SLEEPTALK],aimem)
            score*=1.3
          end
          if checkAImoves([PBMoves::REST],aimem)
            score*=2
          end
          if attacker.pbHasMove?((PBMoves::SPORE)) || attacker.pbHasMove?((PBMoves::SLEEPPOWDER)) || attacker.pbHasMove?((PBMoves::HYPNOSIS)) || attacker.pbHasMove?((PBMoves::SING)) || attacker.pbHasMove?((PBMoves::GRASSWHISTLE)) || attacker.pbHasMove?((PBMoves::DREAMEATER)) || attacker.pbHasMove?((PBMoves::NIGHTMARE)) || (!attacker.abilitynulled && attacker.ability == PBAbilities::BADDREAMS)
            score*=0.3
          end
        else
          score*=0
        end
      when 0x65 # Role Play
        score = 0 if (PBStuff::ABILITYBLACKLIST).include?(opponent.ability)
        score = 0 if (PBStuff::FIXEDABILITIES).include?(attacker.ability)
        if !(opponent.ability ==0 || attacker.ability==opponent.ability || attacker.ability == PBAbilities::DISGUISE) && score != 0
          miniscore = getAbilityDisruptScore(move,opponent,attacker,skill)
          minimini = getAbilityDisruptScore(move,attacker,opponent,skill)
          score *= (1 + (minimini-miniscore))
        else
          score=0
        end
      when 0x66 # Entrainment
        score = 0 if (PBStuff::FIXEDABILITIES).include?(opponent.ability)
        score = 0 if opponent.ability == PBAbilities::TRUANT
        score = 0 if (PBStuff::ABILITYBLACKLIST).include?(attacker.ability) && attacker.ability != PBAbilities::WONDERGUARD
        if !(opponent.ability ==0 || attacker.ability==opponent.ability) && score != 0
          miniscore = getAbilityDisruptScore(move,opponent,attacker,skill)
          minimini = getAbilityDisruptScore(move,attacker,opponent,skill)
          if opponent != attacker.pbPartner
            score *= (1 + (minimini-miniscore))
            if (attacker.ability == PBAbilities::TRUANT)
              score*=3
            elsif (attacker.ability == PBAbilities::WONDERGUARD)
              score=0
            end
          else
            score *= (1 + (miniscore-minimini))
            if (attacker.ability == PBAbilities::WONDERGUARD)
              score +=85
            elsif (attacker.ability == PBAbilities::SPEEDBOOST)
              score +=25
            elsif (opponent.ability == PBAbilities::DEFEATIST)
              score +=30
            elsif (opponent.ability == PBAbilities::SLOWSTART)
              score +=50
            end
          end
        else
          score=0
        end
      when 0x67 # Skill Swap
        score = 0 if (PBStuff::FIXEDABILITIES).include?(attacker.ability) && attacker.ability != PBAbilities::ZENMODE
        score = 0 if (PBStuff::FIXEDABILITIES).include?(opponent.ability) && opponent.ability != PBAbilities::ZENMODE
        score = 0 if opponent.ability == PBAbilities::ILLUSION || attacker.ability == PBAbilities::ILLUSION
        if !(opponent.ability ==0 || attacker.ability==opponent.ability) && score !=0
          miniscore = getAbilityDisruptScore(move,opponent,attacker,skill)
          minimini = getAbilityDisruptScore(move,attacker,opponent,skill)
          if opponent == attacker.pbPartner
            if minimini < 2
              minimini = 2 - minimini
            else
              minimini = 0
            end
          end
          score *= (1 + (minimini-miniscore)*2)
          if (attacker.ability == PBAbilities::TRUANT) && opponent!=attacker.pbPartner
            score*=2
          end
          if (opponent.ability == PBAbilities::TRUANT) && opponent==attacker.pbPartner
            score*=2
          end
        else
          score=0
        end
      when 0x68 # Gastro Acid
        miniscore = getAbilityDisruptScore(move,attacker,opponent,skill)
        score*=miniscore
        if opponent.effects[PBEffects::GastroAcid]  || opponent.effects[PBEffects::Substitute]>0 ||
          (PBStuff::FIXEDABILITIES).include?(opponent.ability)
          score = 0
        end
      when 0x69 # Transform
        if !(attacker.effects[PBEffects::Transform] || attacker.effects[PBEffects::Illusion] || attacker.effects[PBEffects::Substitute]>0)
          miniscore = opponent.level
          miniscore -= attacker.level
          miniscore*=5
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
          miniscore=(10)*statchangecounter(opponent,1,5)
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
          miniscore=(-10)*statchangecounter(attacker,1,5)
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
        else
          score=0
        end
      when 0x6A # Sonicboom
      when 0x6B # Dragon Rage
      when 0x6C # Super Fang
      when 0x6D # Seismic Toss
      when 0x6E # Endeavor
        if attacker.hp > opponent.hp
          score=0
        else
          privar = false
          for i in attacker.moves
            if i.priority>0
              privar=true
            end
          end
          if privar
            score*=1.5
          end
          if ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) || (attitemworks && attacker.item == PBItems::FOCUSSASH)) && attacker.hp == attacker.totalhp
            score*=1.5
          end
          if pbWeather==PBWeather::SANDSTORM && (!opponent.pbHasType?(:ROCK) && !opponent.pbHasType?(:GROUND) && !opponent.pbHasType?(:STEEL))
            score*=1.5
          end
          if opponent.level - attacker.level > 9
            score*=2
          end
        end
      when 0x6F # Psywave
      when 0x70 # Fissure
        if !(opponent.level>attacker.level) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::STURDY)
          if opponent.effects[PBEffects::LockOn]>0
            score*=3.5
          else
            score*=0.7
          end
        else
          score*=0
        end
        if move.id==(PBMoves::FISSURE)
          if $fefieldeffect==17 # Factory
            score*=1.2
            darkvar=false
            for mon in pbParty(attacker.index)
              next if mon.nil?
              if mon.hasType?(:DARK)
                darkvar=true
              end
            end
            if darkvar
              score*=1.5
            end
          end
        end
      when 0x71 # Counter
        maxdam = checkAIdamage(aimem,attacker,opponent,skill)
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=0.5
        end
        if ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) || (attitemworks && attacker.item == PBItems::FOCUSSASH)) && attacker.hp == attacker.totalhp
          score*=1.2
        else
          score*=0.8
          if maxdam>attacker.hp
            score*=0.8
          end
        end
        if $pkmn_move[attacker.lastMoveUsed][0]==0x71
          score*=0.7
        end
        score*=0.6 if checkAImoves(PBStuff::SETUPMOVE,aimem)
        miniscore = attacker.hp*(1.0/attacker.totalhp)
        score*=miniscore
        if opponent.spatk>opponent.attack
          score*=0.3
        end
        score*=0.05 if checkAIbest(aimem,3,[],false,attacker,opponent,skill)
        if $pkmn_move[attacker.lastMoveUsed][0]==0x72
          score*=1.1
        end
      when 0x72 # Mirror Coat
        maxdam = checkAIdamage(aimem,attacker,opponent,skill)
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=0.5
        end
        if ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) || (attitemworks && attacker.item == PBItems::FOCUSSASH)) && attacker.hp == attacker.totalhp
          score*=1.2
        else
          score*=0.8
          if maxdam>attacker.hp
            score*=0.8
          end
        end
        if $pkmn_move[attacker.lastMoveUsed][0]==0x72
          score*=0.7
        end
        score*=0.6 if checkAImoves(PBStuff::SETUPMOVE,aimem)
        miniscore = attacker.hp*(1.0/attacker.totalhp)
        score*=miniscore
        if opponent.spatk<opponent.attack
          score*=0.3
        end
        score*=0.05 if checkAIbest(aimem,2,[],false,attacker,opponent,skill)
        if $pkmn_move[attacker.lastMoveUsed][0]==0x71
          score*=1.1
        end
      when 0x73 # Metal Burst
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=0.01
        end
        if ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) || (attitemworks && attacker.item == PBItems::FOCUSSASH)) && attacker.hp == attacker.totalhp
          score*=1.2
        else
          score*=0.8 if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
        end
        if $pkmn_move[attacker.lastMoveUsed][0]==0x73
          score*=0.7
        end
        movecheck=false
        score*=0.6 if checkAImoves(PBStuff::SETUPMOVE,aimem)
        miniscore = attacker.hp*(1.0/attacker.totalhp)
        score*=miniscore
      when 0x74 # Flame Burst
        if @doublebattle && opponent.pbPartner.hp>0
          score*=1.1
        end
        roastvar=false
        firevar=false
        poisvar=false
        icevar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:GRASS) || mon.hasType?(:BUG)
            roastvar=true
          end
          if mon.hasType?(:FIRE)
            firevar=true
          end
          if mon.hasType?(:POISON)
            poisvar=true
          end
          if mon.hasType?(:ICE)
            icevar=true
          end
        end
        if $fefieldeffect==2 || $fefieldeffect==15 || ($fefieldeffect==33 && $fecounter>1)
          if firevar && !roastvar
            score*=2
          end
        end
        if $fefieldeffect==16
          if firevar
            score*=2
          end
        end
        if $fefieldeffect==11
          if !poisvar
            score*=1.2
          end
          if attacker.hp*(1.0/attacker.totalhp)<0.2
            score*=2
          end
          if pbPokemonCount(pbParty(opponent.index))==1
            score*=5
          end
        end
        if $fefieldeffect==13 || $fefieldeffect==28
          if !icevar
            score*=1.5
          end
        end
      when 0x75 # Surf
        firevar=false
        dragvar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:FIRE)
            firevar=true
          end
          if mon.hasType?(:DRAGON)
            dragvar=true
          end
        end
        if $fefieldeffect==7
          if firevar
            score=0
          else
            score*=2
          end
        end
        if $fefieldeffect==16
          score*=0.7
        end
        if $fefieldeffect==32
          if dragvar || firevar
            score=0
          else
            score*=1.5
          end
        end
      when 0x76 # Earthquake
        darkvar=false
        rockvar=false
        dragvar=false
        icevar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:DARK)
            darkvar=true
          end
          if mon.hasType?(:ROCK)
            rockvar=true
          end
          if mon.hasType?(:DRAGON)
            dragvar=true
          end
          if mon.hasType?(:ICE)
            icevar=true
          end
        end
        if $fefieldeffect==4
          if !darkvar
            score*=1.3
            if rockvar
              score*=1.2
            end
          end
        end
        if $fefieldeffect==25
          if !dragonvar
            score*=1.3
            if rockvar
              score*=1.2
            end
          end
        end
        if $fefieldeffect==13
          if !icevar
            score*=1.5
          end
        end
        if $fefieldeffect==17
          score*=1.2
          if darkvar
            score*=1.3
          end
        end
        if $fefieldeffect==23
          if !(!attacker.abilitynulled && attacker.ability == PBAbilities::ROCKHEAD) && !(!attacker.abilitynulled && attacker.ability == PBAbilities::BULLETPROOF)
            score*=0.7
            if $fecounter >=1
              score *= 0.3
            end
          end
        end
        if $fefieldeffect==30
          if (opponent.stages[PBStats::EVASION] > 0 || (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER) || (oppitemworks && opponent.item == PBItems::LAXINCENSE) ||
            ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) || ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL))
            score*=1.3
          else
            score*=0.5
          end
        end
      when 0x77 # Gust
        fairvar=false
        firevar=false
        poisvar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:FAIRY)
            fairvar=true
          end
          if mon.hasType?(:FIRE)
            firevar=true
          end
          if mon.hasType?(:POISON)
            poisvar=true
          end
        end
        if $fefieldeffect==3
          score*=1.3
          if !fairyvar
            score*=1.3
          else
            score*=0.6
          end
        end
        if $fefieldeffect==7
          if !firevar
            score*=1.8
          else
            score*=0.5
          end
        end
        if $fefieldeffect==11
          if !poisvar
            score*=3
          else
            score*=0.8
          end
        end
      when 0x78 # Twister
        if opponent.effects[PBEffects::Substitute]==0 && !(!opponent.abilitynulled && opponent.ability == PBAbilities::INNERFOCUS)
          if (pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0)
            miniscore=100
            miniscore*=1.3
            if skill>=PBTrainerAI.bestSkill
              if $fefieldeffect==14 # Rocky
                miniscore*=1.2
              end
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::STEADFAST)
              miniscore*=0.3
            end
            miniscore-=100
            if move.addlEffect.to_f != 100
              miniscore*=(move.addlEffect.to_f/100)
            end
            miniscore+=100
            if move.addlEffect.to_f != 100
              if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
                miniscore*=2
              end
            end
            miniscore/=100.0
            score*=miniscore
          end
        end
        fairvar=false
        firevar=false
        poisvar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:FAIRY)
            fairvar=true
          end
          if mon.hasType?(:FIRE)
            firevar=true
          end
          if mon.hasType?(:POISON)
            poisvar=true
          end
        end
        if $fefieldeffect==3
          score*=1.3
          if !fairyvar
            score*=1.3
          else
            score*=0.6
          end
        end
        if $fefieldeffect==7
          if !firevar
            score*=1.8
          else
            score*=0.5
          end
        end
        if $fefieldeffect==11
          if !poisvar
            score*=3
          else
            score*=0.8
          end
        end
        if $fefieldeffect==20
          score*=0.7
        end
      when 0x79 # Fusion Bolt
      when 0x7A # Fusion Flare
      when 0x7B # Venoshock
      when 0x7C # Smelling Salts
        if opponent.status==PBStatuses::PARALYSIS  && opponent.effects[PBEffects::Substitute]<=0
          score*=0.8
          if opponent.speed>attacker.speed && opponent.speed/2.0<attacker.speed
            score*=0.5
          end
        end
      when 0x7D # Wake-Up Slap
        if opponent.status==PBStatuses::SLEEP && opponent.effects[PBEffects::Substitute]<=0
          score*=0.8
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::BADDREAMS) || attacker.pbHasMove?((PBMoves::DREAMEATER)) || attacker.pbHasMove?((PBMoves::NIGHTMARE))
            score*=0.3
          end
          if opponent.pbHasMove?((PBMoves::SNORE)) || opponnet.pbHasMove?((PBMoves::SLEEPTALK))
            score*=1.3
          end
        end
      when 0x7E # Facade
      when 0x7F # Hex
      when 0x80 # Brine
      when 0x81 # Revenge
        if (pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0)
          score*=0.5
        else
          score*=1.5
        end
        if attacker.hp==attacker.totalhp
          score*=1.2
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) || (attitemworks && attacker.item == PBItems::FOCUSSASH)
            score*=1.1
          end
        else
          score*=0.3 if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
        end
        score*=0.8 if checkAImoves(PBStuff::SETUPMOVE,aimem)
        #miniscore=attacker.hp*(1.0/attacker.totalhp)
        #score*=miniscore
      when 0x82 # Assurance
        if (pbRoughStat(opponent,PBStats::SPEED,skill)>attacker.pbSpeed) ^ (@trickroom!=0)
          score*=1.5
        end
      when 0x83 # Round
        if @doublebattle && attacker.pbPartner.pbHasMove?((PBMoves::ROUND))
          score*=1.5
        end
      when 0x84 # Payback
        if (pbRoughStat(opponent,PBStats::SPEED,skill)>attacker.pbSpeed) ^ (@trickroom!=0)
          score*=2
        end
      when 0x85 # Retaliate
      when 0x86 # Acrobatics
      when 0x87 # Weather Ball
      when 0x88 # Pursuit
        miniscore=(-10)*statchangecounter(opponent,1,7,-1)
        miniscore+=100
        miniscore/=100.0
        score*=miniscore
        if opponent.effects[PBEffects::Confusion]>0
          score*=1.2
        end
        if opponent.effects[PBEffects::LeechSeed]>=0
          score*=1.5
        end
        if opponent.effects[PBEffects::Attract]>=0
          score*=1.3
        end
        if opponent.effects[PBEffects::Substitute]>0
          score*=0.7
        end
        if opponent.effects[PBEffects::Yawn]>0
          score*=1.5
        end
        if pbTypeModNoMessages(bettertype,attacker,opponent,move,skill)>4
          score*=1.5
        end
      when 0x89 # Return
      when 0x8A # Frustration
      when 0x8B # Water Spout
        if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=0.5
        end
        if skill>=PBTrainerAI.bestSkill
          if move.id==(PBMoves::WATERSPOUT)
            if $fefieldeffect==7 # Burning
              firevar=false
              watervar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:FIRE)
                  firevar=true
                end
                if mon.hasType?(:WATER)
                  watervar=true
                end
                if !firevar
                  score*=1.5
                end
                if watervar
                  score*=1.5
                end
              end
            end
            if $fefieldeffect==16 # Superheated
              score*=0.7
            end
          end
          if move.id==(PBMoves::ERUPTION)
            if $fefieldeffect==2 # Grassy
              if pbWeather!=PBWeather::RAINDANCE && @field.effects[PBEffects::WaterSport]==0
                firevar=false
                grassvar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:FIRE)
                    firevar=true
                  end
                  if mon.hasType?(:GRASS)
                    grassvar=true
                  end
                  if firevar
                    score*=1.5
                  end
                  if !grassvar
                    score*=1.5
                  end
                end
              end
            end
            if $fefieldeffect==11 # Corromist
              poisonvar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:POISON)
                  poisonvar=true
                end
              end
              if !poisonvar
                score*=1.5
              end
              if (attacker.hp.to_f)/attacker.totalhp<0.5
                score*=2
              end
            end
            if $fefieldeffect==13 # Icy
              watervar=false
              icevar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:WATER)
                  watervar=true
                end
                if mon.hasType?(:ICE)
                  grassvar=true
                end
                if watervar
                  score*=1.3
                end
                if !icevar
                  score*=1.2
                end
              end
            end
            if $fefieldeffect==15 # Forest
              if pbWeather!=PBWeather::RAINDANCE && @field.effects[PBEffects::WaterSport]==0
                firevar=false
                grassvar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:FIRE)
                    firevar=true
                  end
                  if mon.hasType?(:GRASS)
                    grassvar=true
                  end
                  if firevar
                    score*=1.5
                  end
                  if !grassvar
                    score*=1.5
                  end
                end
              end
            end
            if $fefieldeffect==16 # Superheated
              if pbWeather!=PBWeather::RAINDANCE && @field.effects[PBEffects::WaterSport]==0
                firevar=false
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:FIRE)
                    firevar=true
                  end
                  if firevar
                    score*=2
                  end
                end
              end
            end
            if $fefieldeffect==28 # Snowy Mountain
              icevar=false
              for mon in pbParty(attacker.index)
                next if mon.nil?
                if mon.hasType?(:ICE)
                  grassvar=true
                end
                if !icevar
                  score*=1.5
                end
              end
            end
            if $fefieldeffect==33 && $fecounter>=2 # Flower Garden
              if pbWeather!=PBWeather::RAINDANCE && @field.effects[PBEffects::WaterSport]==0
                firevar=false
                grassvar=false
                bugvar=falsw
                for mon in pbParty(attacker.index)
                  next if mon.nil?
                  if mon.hasType?(:FIRE)
                    firevar=true
                  end
                  if mon.hasType?(:GRASS)
                    grassvar=true
                  end
                  if mon.hasType?(:BUG)
                    bugvar=true
                  end
                  if firevar
                    score*=1.5
                  end
                  if !grassvar && !bugvar
                    score*=1.5
                  end
                end
              end
            end
          end
        end
      when 0x8C # Crush Grip
      when 0x8D # Gyro Ball
      when 0x8E # Stored Power
      when 0x8F # Punishment
      when 0x90 # Hidden Power
      when 0x91 # Fury Cutter
        if attacker.status==PBStatuses::PARALYSIS
          score*=0.7
        end
        if attacker.effects[PBEffects::Confusion]>0
          score*=0.7
        end
        if attacker.effects[PBEffects::Attract]>=0
          score*=0.7
        end
        if attacker.stages[PBStats::ACCURACY]<0
          ministat = attacker.stages[PBStats::ACCURACY]
          minimini = 15 * ministat
          minimini += 100
          minimini /= 100.0
          score*=minimini
        end
        miniscore = opponent.stages[PBStats::EVASION]
        miniscore*=(-5)
        miniscore+=100
        miniscore/=100.0
        score*=miniscore
        if attacker.hp==attacker.totalhp
          score*=1.3
        end
        score*=1.5 if checkAIdamage(aimem,attacker,opponent,skill)<(attacker.hp/3.0) && (aimem.length > 0)
        score*=0.8 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
      when 0x92 # Echoed Voice
        if attacker.status==PBStatuses::PARALYSIS
          score*=0.7
        end
        if attacker.effects[PBEffects::Confusion]>0
          score*=0.7
        end
        if attacker.effects[PBEffects::Attract]>=0
          score*=0.7
        end
        if attacker.hp==attacker.totalhp
          score*=1.3
        end
        score*=1.5 if checkAIdamage(aimem,attacker,opponent,skill)<(attacker.hp/3.0) && (aimem.length > 0)
      when 0x93 # Rage
        if attacker.attack>attacker.spatk
          score*=1.2
        end
        if attacker.hp==attacker.totalhp
          score*=1.3
        end
        score*=1.3 if checkAIdamage(aimem,attacker,opponent,skill)<(attacker.hp/4.0) && (aimem.length > 0)
      when 0x94 # Present
        if opponent.hp==opponent.totalhp
          score*=1.2
        end
      when 0x95 # Magnitude
        darkvar=false
        rockvar=false
        dragvar=false
        icevar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:DARK)
            darkvar=true
          end
          if mon.hasType?(:ROCK)
            rockvar=true
          end
          if mon.hasType?(:DRAGON)
            dragvar=true
          end
          if mon.hasType?(:ICE)
            icevar=true
          end
        end
        if $fefieldeffect==4
          if !darkvar
            score*=1.3
            if rockvar
              score*=1.2
            end
          end
        end
        if $fefieldeffect==25
          if !dragonvar
            score*=1.3
            if rockvar
              score*=1.2
            end
          end
        end
        if $fefieldeffect==13
          if !icevar
            score*=1.5
          end
        end
        if $fefieldeffect==17
          score*=1.2
          if darkvar
            score*=1.3
          end
        end
        if $fefieldeffect==23
          if !(!attacker.abilitynulled && attacker.ability == PBAbilities::ROCKHEAD) && !(!attacker.abilitynulled && attacker.ability == PBAbilities::BULLETPROOF)
            score*=0.7
            if $fecounter >=1
              score *= 0.3
            end
          end
        end
        if $fefieldeffect==30
          if (opponent.stages[PBStats::EVASION] > 0 || (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER) || (oppitemworks && opponent.item == PBItems::LAXINCENSE) ||
            ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) || ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL))
            score*=1.3
          else
            score*=0.5
          end
        end
      when 0x96 # Natural Gift
        if !pbIsBerry?(attacker.item) || (!attacker.abilitynulled && attacker.ability == PBAbilities::KLUTZ) || @field.effects[PBEffects::MagicRoom]>0 || attacker.effects[PBEffects::Embargo]>0 || (!opponent.abilitynulled && opponent.ability == PBAbilities::UNNERVE)
          score*=0
        end
      when 0x97 # Trump Card
        if attacker.hp==attacker.totalhp
          score*=1.2
        end
        score*=1.3 if checkAIdamage(aimem,attacker,opponent,skill)<(attacker.hp/3.0) && (aimem.length > 0)
      when 0x98 # Reversal
        if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=1.1
          if attacker.hp<attacker.totalhp
            score*=1.3
          end
        end
      when 0x99 # Electro Ball
      when 0x9A # Low Kick
      when 0x9B # Heat Crash
      when 0x9C # Helping Hand
        if @doublebattle
          effvar = false
          for i in attacker.moves
            if pbTypeModNoMessages(i.type,attacker,opponent,i,skill)>=4
              effvar = true
            end
          end
          if !effvar
            score*=2
          end
          if ((attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && ((attacker.pbSpeed<pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0))
            score*=1.2
            if attacker.hp*(1.0/attacker.totalhp) < 0.33
              score*=1.5
            end
            if attacker.pbPartner.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill) && attacker.pbPartner.pbSpeed<pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)
              score*=1.5
            end
          end
          ministat = [attacker.pbPartner.attack,attacker.pbPartner.spatk].max
          minimini = [attacker.attack,attacker.spatk].max
          ministat-=minimini
          ministat+=100
          ministat/=100.0
          score*=ministat
          if attacker.pbPartner.hp==0
            score*=0
          end
        else
          score*=0
        end
      when 0x9D # Mud Sport
        if @field.effects[PBEffects::MudSport]==0
          eff1 = PBTypes.getCombinedEffectiveness(PBTypes::ELECTRIC,attacker.type1,attacker.type2)
          eff2 = PBTypes.getCombinedEffectiveness(PBTypes::ELECTRIC,attacker.pbPartner.type1,attacker.pbPartner.type2)
          if eff1>4 || eff2>4 && opponent.hasType?(:ELECTRIC)
            score*=1.5
          end
          elevar=false
          for mon in pbParty(attacker.index)
            next if mon.nil?
            if mon.hasType?(:ELECTRIC)
              elevar=true
            end
          end
          if elevar
            score*=0.7
          end
          if $fefieldeffect==1
            if !elevar
              score*=2
            else
              score*=0.3
            end
          end
        else
          score*=0
        end
      when 0x9E # Water Sport
        if @field.effects[PBEffects::WaterSport]==0
          eff1 = PBTypes.getCombinedEffectiveness(PBTypes::FIRE,attacker.type1,attacker.type2)
          eff2 = PBTypes.getCombinedEffectiveness(PBTypes::FIRE,attacker.pbPartner.type1,attacker.pbPartner.type2)
          if eff1>4 || eff2>4 && opponent.hasType?(:FIRE)
            score*=1.5
          end
          firevar=false
          grassvar=false
          bugvar=false
          for mon in pbParty(attacker.index)
            next if mon.nil?
            if mon.hasType?(:FIRE)
              firevar=true
            end
            if mon.hasType?(:GRASS)
              grassvar=true
            end
            if mon.hasType?(:BUG)
              bugvar=true
            end
          end
          if firevar
            score*=0.7
          end
          if $fefieldeffect==7
            if !firevar
              score*=2
            else
              score*=0
            end
          elsif $fefieldeffect==16
            score*=0.7
            if !firevar
              score*=1.8
            else
              score*=0
            end
          elsif $fefieldeffect==2 || $fefieldeffect==15 || $fefieldeffect==33
            if !attacker.hasType?(:FIRE) && opponent.hasType?(:FIRE)
              score*=3
            end
            if grassvar || bugvar
              score*=2
              if $fefieldeffect==33 && $fecounter<4
                score*=3
              end
            end
            if firevar
              score*=0.5
            end
          end
        else
          score*=0
        end
      when 0x9F # Judgement
      when 0xA0 # Frost Breath
        thisinitial = score
        if !(!opponent.abilitynulled && opponent.ability == PBAbilities::BATTLEARMOR) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::SHELLARMOR) && attacker.effects[PBEffects::LaserFocus]==0
          miniscore = 100
          ministat = 0
          ministat += opponent.stages[PBStats::DEFENSE] if opponent.stages[PBStats::DEFENSE]>0
          ministat += opponent.stages[PBStats::SPDEF] if opponent.stages[PBStats::SPDEF]>0
          miniscore += 10*ministat
          ministat = 0
          ministat -= attacker.stages[PBStats::ATTACK] if attacker.stages[PBStats::ATTACK]<0
          ministat -= attacker.stages[PBStats::SPATK] if attacker.stages[PBStats::SPATK]<0
          miniscore += 10*ministat
          if attacker.effects[PBEffects::FocusEnergy]>0
            miniscore -= 10*attacker.effects[PBEffects::FocusEnergy]
          end
          miniscore/=100.0
          score*=miniscore
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::ANGERPOINT) && opponent.stages[PBStats::ATTACK]!=6
            if opponent == attacker.pbPartner
              if opponent.attack>opponent.spatk
                if thisinitial>99
                  score=0
                else
                  score = (100-thisinitial)
                  enemy1 = attacker.pbOppositeOpposing
                  enemy2 = enemy1.pbPartner
                  if opponent.pbSpeed > enemy1.pbSpeed && opponent.pbSpeed > enemy2.pbSpeed
                    score*=1.3
                  else
                    score*=0.7
                  end
                end
              end
            else
              if thisinitial<100
                score*=0.7
                if opponent.attack>opponent.spatk
                  score*=0.2
                end
              end
            end
          else
            if opponent == attacker.pbPartner
              score = 0
            end
          end
        else
          score*=0.7
        end
      when 0xA1 # Lucky Chant
        if attacker.pbOwnSide.effects[PBEffects::LuckyChant]==0  && !(!attacker.abilitynulled && attacker.ability == PBAbilities::BATTLEARMOR) || !(!attacker.abilitynulled && attacker.ability == PBAbilities::SHELLARMOR) && (opponent.effects[PBEffects::FocusEnergy]>1 || opponent.effects[PBEffects::LaserFocus]>0)
          score+=20
        end
      when 0xA2 # Reflect
        if attacker.pbOwnSide.effects[PBEffects::Reflect]<=0
          score*=1.2
          if attacker.pbOwnSide.effects[PBEffects::AuroraVeil]>0
            score*=0.5
          end
          if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
            score*=1.3
          end
          if (attitemworks && attacker.item == PBItems::LIGHTCLAY)
            score*=1.5
          end
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.1
            if skill>=PBTrainerAI.bestSkill
              if aimem.length > 0
                maxdam=0
                for j in aimem
                  if !j.pbIsPhysical?(j.type)
                    next
                  end
                  tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)
                  maxdam=tempdam if maxdam<tempdam
                end
                if maxdam>attacker.hp && (maxdam/2.0)<attacker.hp
                  score*=2
                end
              end
            end
          end
          livecount=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount+=1 if i.hp!=0
          end
          if livecount<=2
            score*=0.7
            if livecount==1
              score*=0.7
            end
          end
          if (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
            score*=1.3
          end
          score*=0.1 if checkAImoves(PBStuff::PBStuff::SCREENBREAKERMOVE,aimem)
        else
          score=0
        end
      when 0xA3 # Light Screen
        if attacker.pbOwnSide.effects[PBEffects::LightScreen]<=0
          score*=1.2
          if attacker.pbOwnSide.effects[PBEffects::AuroraVeil]>0
            score*=0.5
          end
          if pbRoughStat(opponent,PBStats::ATTACK,skill)<pbRoughStat(opponent,PBStats::SPATK,skill)
            score*=1.3
          end
          if (attitemworks && attacker.item == PBItems::LIGHTCLAY)
            score*=1.5
          end
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.1
            if aimem.length > 0
              maxdam=0
              for j in aimem
                if !j.pbIsSpecial?(j.type)
                  next
                end
                tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)
                maxdam=tempdam if maxdam<tempdam
              end
              if maxdam>attacker.hp && (maxdam/2.0)<attacker.hp
                score*=2
              end
            end
          end
          livecount=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount+=1 if i.hp!=0
          end
          if livecount<=2
            score*=0.7
            if livecount==1
              score*=0.7
            end
          end
          if (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
            score*=1.3
          end
          score*=0.1 if checkAImoves(PBStuff::PBStuff::SCREENBREAKERMOVE,aimem)
        else
          score=0
        end
      when 0xA4 # Secret Power
        score*=1.2
      when 0xA5 # Never Miss
        if score==110
          score*=1.05
        end
        if !(!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD)
          if attacker.stages[PBStats::ACCURACY]<0
            miniscore = (-5)*attacker.stages[PBStats::ACCURACY]
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
          if opponent.stages[PBStats::EVASION]>0
            miniscore = (5)*opponent.stages[PBStats::EVASION]
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
          if (oppitemworks && opponent.item == PBItems::LAXINCENSE) || (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER)
            score*=1.2
          end
          if ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) || ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL)
            score*=1.3
          end
          if opponent.vanished && ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0))
            score*=3
          end
        end
      when 0xA6 # Lock On
        if opponent.effects[PBEffects::LockOn]>0 ||  opponent.effects[PBEffects::Substitute]>0
          score*=0
        else
          if attacker.pbHasMove?((PBMoves::INFERNO)) || attacker.pbHasMove?((PBMoves::ZAPCANNON)) || attacker.pbHasMove?((PBMoves::DYNAMICPUNCH))
            if !(!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD)
              score*=3
            end
          end
          if attacker.pbHasMove?((PBMoves::GUILLOTINE)) || attacker.pbHasMove?((PBMoves::SHEERCOLD)) || attacker.pbHasMove?((PBMoves::GUILLOTINE)) || attacker.pbHasMove?((PBMoves::FISSURE)) || attacker.pbHasMove?((PBMoves::HORNDRILL))
            score*=10
          end
          ministat=0
          ministat = attacker.stages[PBStats::ACCURACY] if attacker.stages[PBStats::ACCURACY]<0
          ministat*=10
          ministat+=100
          ministat/=100.0
          score*=ministat
          ministat = opponent.stages[PBStats::EVASION]
          ministat*=10
          ministat+=100
          ministat/=100.0
          score*=ministat
        end
        if $fefieldeffect==37
          if (move.id == PBMoves::MINDREADER)
            if attacker.stages[PBStats::SPATK]<6
              score+=10
            end
            if attacker.spatk>attacker.attack
              score*=2
            end
            if attacker.hp==attacker.totalhp
              score*=1.5
            else
              score*=0.8
            end
            if roles.include?(PBMonRoles::SWEEPER)
              score*=1.3
            end
            if attacker.hp<attacker.totalhp*0.5
              score*=0.5
            end
          end
        end
      when 0xA7 # Foresight
        if opponent.effects[PBEffects::Foresight]
          score*=0
        else
          ministat = 0
          ministat = opponent.stages[PBStats::EVASION] if opponent.stages[PBStats::EVASION]>0
          ministat*=10
          ministat+=100
          ministat/=100.0
          score*=ministat
          if opponent.pbHasType?(:GHOST)
            score*=1.5
            effectvar = false
            for i in attacker.moves
              next if i.basedamage==0
              if !(i.type == PBTypes::NORMAL) && !(i.type == PBTypes::FIGHTING)
                effectvar = true
                break
              end
            end
            if !effectvar && !(!attacker.abilitynulled && attacker.ability == PBAbilities::SCRAPPY)
              score*=5
            end
          end
        end
      when 0xA8 # Miracle Eye
        if opponent.effects[PBEffects::MiracleEye]
          score*=0
        else
          ministat = 0
          ministat = opponent.stages[PBStats::EVASION] if opponent.stages[PBStats::EVASION]>0
          ministat*=10
          ministat+=100
          ministat/=100.0
          score*=ministat
          if opponent.pbHasType?(:DARK)
            score*=1.1
            effectvar = false
            for i in attacker.moves
              next if i.basedamage==0
              if !(i.type == PBTypes::PSYCHIC)
                effectvar = true
                break
              end
            end
            if !effectvar
              score*=2
            end
          end
        end
        if $fefieldeffect==37 || $fefieldeffect==29 || $fefieldeffect==31
          if attacker.stages[PBStats::SPATK]<6
            score+=10
          end
          if attacker.spatk>attacker.attack
            score*=2
          end
          if attacker.hp==attacker.totalhp
            score*=1.5
          else
            score*=0.8
          end
          if roles.include?(PBMonRoles::SWEEPER)
            score*=1.3
          end
          if attacker.hp<attacker.totalhp*0.5
            score*=0.5
          end
        end
      when 0xA9 # Chip Away
        ministat = 0
        ministat+=opponent.stages[PBStats::EVASION] if opponent.stages[PBStats::EVASION]>0
        ministat+=opponent.stages[PBStats::DEFENSE] if opponent.stages[PBStats::DEFENSE]>0
        ministat+=opponent.stages[PBStats::SPDEF] if opponent.stages[PBStats::SPDEF]>0
        ministat*=5
        ministat+=100
        ministat/=100.0
        score*=ministat
      when 0xAA # Protect
        score*=0.3 if opponent.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SPEEDBOOST) && attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          score*=4
          #experimental -- cancels out drop if killing moves
          if initialscores.length>0
            score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
          end
          #end experimental
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON)) || attacker.effects[PBEffects::Ingrain] || attacker.effects[PBEffects::AquaRing] || $fefieldeffect==2
          score*=1.2
        end
        if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN
          score*=1.2
          if opponent.effects[PBEffects::Toxic]>0
            score*=1.3
          end
        end
        if attacker.status==PBStatuses::POISON || attacker.status==PBStatuses::BURN
          score*=0.7
          if attacker.effects[PBEffects::Toxic]>0
            score*=0.3
          end
        end
        if opponent.effects[PBEffects::LeechSeed]>=0
          score*=1.3
        end
        if opponent.effects[PBEffects::PerishSong]!=0
          score*=2
        end
        if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
          score*=0.3
        end
        if opponent.vanished
          score*=2
          if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.5
          end
        end
        score*=0.1 if checkAImoves(PBStuff::PROTECTIGNORINGMOVE,aimem)
        if attacker.effects[PBEffects::Wish]>0
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=10
          else
            score*=3
          end
        end
        ratesharers=[
        391,   # Protect
        121,   # Detect
        122,   # Quick Guard
        515,   # Wide Guard
        361,   # Endure
        584,   # King's Shield
        603,    # Spiky Shield
        641    # Baneful Bunker
          ]
        if ratesharers.include?(attacker.lastMoveUsed)
          score/=(attacker.effects[PBEffects::ProtectRate]*2.0)
        end
      when 0xAB # Quick Guard
        ratesharers=[
        391,   # Protect
        121,   # Detect
        122,   # Quick Guard
        515,   # Wide Guard
        361,   # Endure
        584,   # King's Shield
        603,    # Spiky Shield
        641    # Baneful Bunker
          ]
        if ratesharers.include?(attacker.lastMoveUsed)
          score/=(attacker.effects[PBEffects::ProtectRate]*2.0)
        end

        if ((!opponent.abilitynulled && opponent.ability == PBAbilities::GALEWINGS) && opponent.hp == opponent.totalhp) || ((!opponent.abilitynulled && opponent.ability == PBAbilities::PRANKSTER) && attacker.pbHasType?(:POISON)) || checkAIpriority(aimem)
          score*=2
          if @doublebattle
            score*=1.3
            score*=0.3 if checkAIhealing(aimem) || checkAImoves(PBStuff::SETUPMOVE,aimem)
            score*=0.1 if checkAImoves(PBStuff::PROTECTIGNORINGMOVE,aimem)
            if attacker.effects[PBEffects::Wish]>0
              score*=2 if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp || (attacker.pbPartner.hp*(1.0/attacker.pbPartner.totalhp))<0.25
            end
          end
        else
          score*=0
        end
      when 0xAC # Wide Guard
        ratesharers=[
        391,   # Protect
        121,   # Detect
        122,   # Quick Guard
        515,   # Wide Guard
        361,   # Endure
        584,   # King's Shield
        603,    # Spiky Shield
        641    # Baneful Bunker
          ]
        if ratesharers.include?(attacker.lastMoveUsed)
          score/=(attacker.effects[PBEffects::ProtectRate]*2.0)
        end
        widevar = false
        if aimem.length > 0
          for j in aimem
            widevar = true if (j.target == PBTargets::AllOpposing || j.target == PBTargets::AllNonUsers)
          end
        end
        if @doublebattle
          if widevar
            score*=2
            score*=0.3 if checkAIhealing(aimem) || checkAImoves(PBStuff::SETUPMOVE,aimem)
            score*=0.1 if checkAImoves(PBStuff::PROTECTIGNORINGMOVE,aimem)
            if attacker.effects[PBEffects::Wish]>0
              maxdam = checkAIdamage(aimem,attacker,opponent,skill)
              if maxdam>attacker.hp || (attacker.pbPartner.hp*(1.0/attacker.pbPartner.totalhp))<0.25
                score*=2
              end
            end
            if $fefieldeffect==11
              score*=2 if checkAImoves([PBMoves::HEATWAVE,PBMoves::LAVAPLUME,PBMoves::ERUPTION,PBMoves::MINDBLOWN],aimem)
            end
            if $fefieldeffect==23
              score*=2 if checkAImoves([PBMoves::MAGNITUDE,PBMoves::EARTHQUAKE,PBMoves::BULLDOZE],aimem)
            end
            if $fefieldeffect==30
              score*=2 if (checkAImoves([PBMoves::MAGNITUDE,PBMoves::EARTHQUAKE,PBMoves::BULLDOZE],aimem) || checkAImoves([PBMoves::HYPERVOICE,PBMoves::BOOMBURST],aimem))
            end
          end
        else
          score*=0
        end
      when 0xAD # Feint
        if checkAImoves(PBStuff::PROTECTIGNORINGMOVE,aimem)
          score*=1.1
          ratesharers=[
          391,   # Protect
          121,   # Detect
          122,   # Quick Guard
          515,   # Wide Guard
          361,   # Endure
          584,   # King's Shield
          603,    # Spiky Shield
          641    # Baneful Bunker
            ]
          if !ratesharers.include?(opponent.lastMoveUsed)
            score*=1.2
          end
        end
      when 0xAE # Mirror Move
        if opponent.lastMoveUsed>0
          mirrored = PBMove.new(opponent.lastMoveUsed)
          mirrmove = PokeBattle_Move.pbFromPBMove(self,mirrored)
          if mirrmove.flags&0x10==0
            score*=0
          else
            rough = pbRoughDamage(mirrmove,attacker,opponent,skill,mirrmove.basedamage)
            mirrorscore = pbGetMoveScore(mirrmove,attacker,opponent,skill,rough,initialscores,scoreindex)
            score = mirrorscore
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=0.5
            end
          end
        else
          score*=0
        end
      when 0xAF # Copycat
        if opponent.lastMoveUsed>0  && opponent.effects[PBEffects::Substitute]<=0
          copied = PBMove.new(opponent.lastMoveUsed)
          copymove = PokeBattle_Move.pbFromPBMove(self,copied)
          if copymove.flags&0x10==0
            score*=0
          else
            rough = pbRoughDamage(copymove,attacker,opponent,skill,copymove.basedamage)
            copyscore = pbGetMoveScore(copymove,attacker,opponent,skill,rough,initialscores,scoreindex)
            score = copyscore
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=0.5
            end
            if $fefieldeffect==30
              score*=1.5
            end
          end
        else
          score*=0
        end
      when 0xB0 # Me First
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          if checkAImoves(PBStuff::SETUPMOVE,aimem)
            score*=0.8
          else
            score*=1.5
          end
          if checkAIpriority(aimem) || (!opponent.abilitynulled && opponent.ability == PBAbilities::PRANKSTER) || ((!opponent.abilitynulled && opponent.ability == PBAbilities::GALEWINGS) && opponent.hp==opponent.totalhp)
            score*=0.6
          else
            score*=1.5
          end
          if opponent.hp>0 && initialscores.length>0
            if checkAIdamage(aimem,attacker,opponent,skill)/(1.0*opponent.hp)>initialscores.max
              score*=2
            else
              score*=0.5
            end
          end
        else
          score*=0
        end
      when 0xB1 # Magic Coat
        if attacker.lastMoveUsed>0
          olddata = PBMove.new(attacker.lastMoveUsed)
          oldmove = PokeBattle_Move.pbFromPBMove(self,olddata)
          if oldmove.function==0xB1
            score*=0.5
          else
            if attacker.hp==attacker.totalhp
              score*=1.5
            end
            statvar = true
            for i in opponent.moves
              if i.basedamage>0
                statvar=false
              end
            end
            if statvar
              score*=3
            end
          end
        else
          if attacker.hp==attacker.totalhp
            score*=1.5
          end
          statvar = true
          for i in opponent.moves
            if i.basedamage>0
              statvar=false
            end
          end
          if statvar
            score*=3
          end
        end
      when 0xB2 # Snatch
        if attacker.lastMoveUsed>0
          olddata = PBMove.new(attacker.lastMoveUsed)
          oldmove = PokeBattle_Move.pbFromPBMove(self,olddata)
          if oldmove.function==0xB2
            score*=0.5
          else
            if opponent.hp==opponent.totalhp
              score*=1.5
            end
            score*=2 if checkAImoves(PBStuff::SETUPMOVE,aimem)
            if opponent.attack>opponent.spatk
              if attacker.attack>attacker.spatk
                score*=1.5
              else
                score*=0.7
              end
            else
              if attacker.spatk>attacker.attack
                score*=1.5
              else
                score*=0.7
              end
            end
          end
        else
          if opponent.hp==opponent.totalhp
            score*=1.5
          end
          score*=2 if checkAImoves(PBStuff::SETUPMOVE,aimem)
          if opponent.attack>opponent.spatk
            if attacker.attack>attacker.spatk
              score*=1.5
            else
              score*=0.7
            end
          else
            if attacker.spatk>attacker.attack
              score*=1.5
            else
              score*=0.7
            end
          end
        end
      when 0xB3 # Nature Power
        case $fefieldeffect
          when 33
            if $fecounter == 4
              newmove=PBMoves::PETALBLIZZARD
            else
              newmove=PBMoves::GROWTH
            end
          else
            if $fefieldeffect > 0 && $fefieldeffect <= 37
              naturemoves = FieldEffects::NATUREMOVES
              newmove= naturemoves[$fefieldeffect]
            else
              newmove=PBMoves::TRIATTACK
            end
          end
        newdata = PBMove.new(newmove)
        naturemove = PokeBattle_Move.pbFromPBMove(self,newdata)
        if naturemove.basedamage<=0
          naturedam=pbStatusDamage(naturemove)
        else
          tempdam=pbRoughDamage(naturemove,attacker,opponent,skill,naturemove.basedamage)
          naturedam=(tempdam*100)/(opponent.hp.to_f)
        end
        naturedam=110 if naturedam>110
        score = pbGetMoveScore(naturemove,attacker,opponent,skill,naturedam)
      when 0xB4 # Sleep Talk
        if attacker.status==PBStatuses::SLEEP
          if attacker.statusCount<=1
            score*=0
          else
            if attacker.pbHasMove?((PBMoves::SNORE))
              count=-1
              for k in attacker.moves
                count+=1
                if k.id == 312 # Snore index
                  break
                end
              end
              if initialscores
                snorescore = initialscores[count]
                otherscores = 0
                for s in initialscores
                  next if s.index==scoreindex
                  next if s.index==count
                  otherscores+=s
                end
                otherscores/=2.0
                if otherscores>snorescore
                  score*=0.1
                else
                  score*=5
                end
              end
            end
          end
        else
          score*=0
        end
      when 0xB5 # Assist
        if attacker.pbNonActivePokemonCount > 0
          if initialscores.length>0
            scorecheck = false
            for s in initialscores
              next if initialscores.index(s) == scoreindex
              scorecheck=true if s>25
            end
            if scorecheck
              score*=0.5
            else
              score*=1.5
            end
          end
        else
          score*=0
        end
      when 0xB6 # Metronome
        if $fefieldeffect==24
          if initialscores.length>0
            scorecheck = false
            for s in initialscores
              next if initialscores.index(s) == scoreindex
              scorecheck=true if s>40
            end
            if scorecheck
              score*=0.8
            else
              score*=2
            end
          end
        else
          if initialscores.length>0
            scorecheck = false
            for s in initialscores
              next if initialscores.index(s) == scoreindex
              scorecheck=true if s>21
            end
            if scorecheck
              score*=0.5
            else
              score*=1.2
            end
          end
        end
      when 0xB7 # Torment
        olddata = PBMove.new(attacker.lastMoveUsed)
        oldmove = PokeBattle_Move.pbFromPBMove(self,olddata)
        maxdam = 0
        moveid = -1
        if aimem.length > 0
          for j in aimem
            tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)
            if tempdam>maxdam
              maxdam=tempdam
              moveid = j.id
            end
          end
        end
        if opponent.effects[PBEffects::Torment] || (pbCheckSideAbility(:AROMAVEIL,opponent)!=nil && !(opponent.moldbroken))
          score=0
        else
          if ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::PRANKSTER) && !opponent.pbHasType?(:DARK))
            score*=1.2
          else
            score*=0.7
          end
          if oldmove.basedamage>0
            score*=1.5
            if moveid == oldmove.id
              score*=1.3
              if maxdam*3<attacker.totalhp
                score*=1.5
              end
            end
            if attacker.pbHasMove?((PBMoves::PROTECT))
              score*=1.5
            end
            if (attitemworks && attacker.item == PBItems::LEFTOVERS)
              score*=1.3
            end
          else
            score*=0.5
          end
        end
      when 0xB8 # Imprison
        if attacker.effects[PBEffects::Imprison]
          score*=0
        else
          miniscore=1
          ourmoves = []
          olddata = PBMove.new(attacker.lastMoveUsed)
          oldmove = PokeBattle_Move.pbFromPBMove(self,olddata)
          for m in attacker.moves
            ourmoves.push(m.id) unless m.id<1
          end
          if ourmoves.include?(oldmove.id)
            score*=1.3
          end
          if aimem.length > 0
            for j in aimem
              if ourmoves.include?(j.id)
                miniscore+=1
                if j.isHealingMove?
                  score*=1.5
                end
              else
                score*=0.5
              end
            end
          end
          score*=miniscore
        end
      when 0xB9 # Disable
        olddata = PBMove.new(opponent.lastMoveUsed)
        oldmove = PokeBattle_Move.pbFromPBMove(self,olddata)
        maxdam = 0
        moveid = -1
        if aimem.length > 0
          for j in aimem
            tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)
            if tempdam>maxdam
              maxdam=tempdam
              moveid = j.id
            end
          end
        end
        if oldmove.id == -1 && (((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::PRANKSTER) && !opponent.pbHasType?(:DARK)))
          score=0
        end
        if opponent.effects[PBEffects::Disable]>0 || (pbCheckSideAbility(:AROMAVEIL,opponent)!=nil && !(opponent.moldbroken))
          score=0
        else
          if ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::PRANKSTER) && !opponent.pbHasType?(:DARK))
            score*=1.2
          else
            score*=0.3
          end
          if oldmove.basedamage>0 || oldmove.isHealingMove?
            score*=1.5
            if moveid == oldmove.id
              score*=1.3
              if maxdam*3<attacker.totalhp
                score*=1.5
              end
            end
          else
            score*=0.5
          end
        end
      when 0xBA # Taunt
        olddata = PBMove.new(attacker.lastMoveUsed)
        oldmove = PokeBattle_Move.pbFromPBMove(self,olddata)
        if opponent.effects[PBEffects::Taunt]>0 || (pbCheckSideAbility(:AROMAVEIL,opponent)!=nil && !(opponent.moldbroken))
          score=0
        else
          if ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::PRANKSTER) && !opponent.pbHasType?(:DARK))
            score*=1.5
          else
            score*=0.7
          end
          if (pbGetMonRole(opponent,attacker,skill)).include?(PBMonRoles::LEAD)
            score*=1.2
          else
            score*=0.8
          end
          if opponent.turncount<=1
            score*=1.1
          else
            score*=0.9
          end
          if oldmove.isHealingMove?
            score*=1.3
          end
          if @doublebattle
            score *= 0.6
          end
        end
      when 0xBB # Heal Block
        olddata = PBMove.new(attacker.lastMoveUsed)
        oldmove = PokeBattle_Move.pbFromPBMove(self,olddata)
        if opponent.effects[PBEffects::HealBlock]>0 || (pbCheckSideAbility(:AROMAVEIL,opponent)!=nil && !(opponent.moldbroken)) || opponent.effects[PBEffects::Substitute]>0
          score=0
        else
          if ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::PRANKSTER) && !opponent.pbHasType?(:DARK))
            score*=1.5
          end
          if oldmove.isHealingMove?
            score*=2.5
          end
          if (oppitemworks && opponent.item == PBItems::LEFTOVERS)
            score*=1.3
          end
        end
      when 0xBC # Encore
        olddata = PBMove.new(opponent.lastMoveUsed)
        oldmove = PokeBattle_Move.pbFromPBMove(self,olddata)
        if opponent.effects[PBEffects::Encore]>0 || (pbCheckSideAbility(:AROMAVEIL,opponent)!=nil && !(opponent.moldbroken))
          score=0
        else
          if opponent.lastMoveUsed<=0
            score*=0.2
          else
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=1.5
            else
              if ((!attacker.abilitynulled && attacker.ability == PBAbilities::PRANKSTER) && !opponent.pbHasType?(:DARK))
                score*=2
              else
                score*=0.2
              end
            end
            if oldmove.basedamage>0 && pbRoughDamage(oldmove,opponent,attacker,skill,oldmove.basedamage)*5>attacker.hp
              score*=0.3
            else
              if opponent.stages[PBStats::SPEED]>0
                if (opponent.pbHasType?(:DARK) || !(!attacker.abilitynulled && attacker.ability == PBAbilities::PRANKSTER) || (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST))
                  score*=0.5
                else
                  score*=2
                end
              else
                score*=2
              end
            end
            if $fefieldeffect == 6
              score*=1.5
            end
          end
        end
      when 0xBD # Double Kick
        if (oppitemworks && opponent.item == PBItems::ROCKYHELMET) || (!opponent.abilitynulled && opponent.ability == PBAbilities::IRONBARBS) || (!opponent.abilitynulled && opponent.ability == PBAbilities::ROUGHSKIN)
          score*=0.9
        end
        if opponent.hp==opponent.totalhp && ((oppitemworks && opponent.item == PBItems::FOCUSSASH) || (!opponent.abilitynulled && opponent.ability == PBAbilities::STURDY))
          score*=1.3
        end
        if opponent.effects[PBEffects::Substitute]>0
          score*=1.3
        end
        if (attitemworks && attacker.item == PBItems::RAZORFANG) || (attitemworks && attacker.item == PBItems::KINGSROCK)
          score*=1.1
        end
      when 0xBE # Twinneedle
        if opponent.pbCanPoison?(false)
          miniscore=100
          miniscore*=1.2
          ministat=0
          ministat+=opponent.stages[PBStats::DEFENSE]
          ministat+=opponent.stages[PBStats::SPDEF]
          ministat+=opponent.stages[PBStats::EVASION]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::NATURALCURE)
            miniscore*=0.3
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::MARVELSCALE)
            miniscore*=0.7
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::TOXICBOOST) || (!opponent.abilitynulled && opponent.ability == PBAbilities::GUTS)
            miniscore*=0.2
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::POISONHEAL) || (!opponent.abilitynulled && opponent.ability == PBAbilities::MAGICGUARD)
            miniscore*=0.1
          end
          miniscore*=0.1 if checkAImoves([PBMoves::REST],aimem)
          miniscore*=0.2 if checkAImoves([PBMoves::FACADE],aimem)
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            miniscore*=1.5
          end
          if initialscores.length>0
            miniscore*=1.2 if hasbadmoves(initialscores,scoreindex,30)
          end
          if attacker.pbHasMove?((PBMoves::VENOSHOCK)) ||
            attacker.pbHasMove?((PBMoves::VENOMDRENCH)) ||
            (!attacker.abilitynulled && attacker.ability == PBAbilities::MERCILESS)
            miniscore*=1.6
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SHEDSKIN)
            miniscore*=0.7
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
        end
        if (oppitemworks && opponent.item == PBItems::ROCKYHELMET) || (!opponent.abilitynulled && opponent.ability == PBAbilities::IRONBARBS) || (!opponent.abilitynulled && opponent.ability == PBAbilities::ROUGHSKIN)
          score*=0.8
        end
        if opponent.hp==opponent.totalhp && ((oppitemworks && opponent.item == PBItems::FOCUSSASH) || (!opponent.abilitynulled && opponent.ability == PBAbilities::STURDY))
          score*=1.3
        end
        if opponent.effects[PBEffects::Substitute]>0
          score*=1.3
        end
        if (attitemworks && attacker.item == PBItems::RAZORFANG) || (attitemworks && attacker.item == PBItems::KINGSROCK)
          score*=1.1
        end
      when 0xBF # Triple Kick
        if (oppitemworks && opponent.item == PBItems::ROCKYHELMET) || (!opponent.abilitynulled && opponent.ability == PBAbilities::IRONBARBS) || (!opponent.abilitynulled && opponent.ability == PBAbilities::ROUGHSKIN)
          score*=0.8
        end
        if opponent.hp==opponent.totalhp && ((oppitemworks && opponent.item == PBItems::FOCUSSASH) || (!opponent.abilitynulled && opponent.ability == PBAbilities::STURDY))
          score*=1.3
        end
        if opponent.effects[PBEffects::Substitute]>0
          score*=1.3
        end
        if (attitemworks && attacker.item == PBItems::RAZORFANG) || (attitemworks && attacker.item == PBItems::KINGSROCK)
          score*=1.2
        end
      when 0xC0 # Bullet Seed
        if (oppitemworks && opponent.item == PBItems::ROCKYHELMET) || (!opponent.abilitynulled && opponent.ability == PBAbilities::IRONBARBS) || (!opponent.abilitynulled && opponent.ability == PBAbilities::ROUGHSKIN)
          score*=0.7
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::SKILLLINK)
            score*=0.5
          end
        end
        if opponent.hp==opponent.totalhp && ((oppitemworks && opponent.item == PBItems::FOCUSSASH) || (!opponent.abilitynulled && opponent.ability == PBAbilities::STURDY))
          score*=1.3
        end
        if opponent.effects[PBEffects::Substitute]>0
          score*=1.3
        end
        if (attitemworks && attacker.item == PBItems::RAZORFANG) || (attitemworks && attacker.item == PBItems::KINGSROCK)
          score*=1.3
        end
      when 0xC1 # Beat Up
        count = -1
        for mon in pbParty(attacker.index)
          next if mon.nil?
          count+=1 if mon.hp>0
        end
        if count>0
          if (oppitemworks && opponent.item == PBItems::ROCKYHELMET) || (!opponent.abilitynulled && opponent.ability == PBAbilities::IRONBARBS) || (!opponent.abilitynulled && opponent.ability == PBAbilities::ROUGHSKIN)
            score*=0.7
          end
          if opponent.hp==opponent.totalhp && ((oppitemworks && opponent.item == PBItems::FOCUSSASH) || (!opponent.abilitynulled && opponent.ability == PBAbilities::STURDY))
            score*=1.3
          end
          if opponent.effects[PBEffects::Substitute]>0
            score*=1.3
          end
          if (attitemworks && attacker.item == PBItems::RAZORFANG) || (attitemworks && attacker.item == PBItems::KINGSROCK)
            score*=1.3
          end
          if opponent == attacker.pbPartner && (!opponent.abilitynulled && opponent.ability == PBAbilities::JUSTIFIED)
            if opponent.stages[PBStats::ATTACK]<1 && opponent.attack>opponent.spatk
              score= 100-thisinitial
              enemy1 = attacker.pbOppositeOpposing
              enemy2 = enemy1.pbPartner
              if opponent.pbSpeed > enemy1.pbSpeed && opponent.pbSpeed > enemy2.pbSpeed
                score*=1.3
              else
                score*=0.7
              end
            end
          end
          if opponent == attacker.pbPartner && !(!opponent.abilitynulled && opponent.ability == PBAbilities::JUSTIFIED)
            score=0
          end
        end
      when 0xC2 # Hyper Beam
        if $fefieldeffect == 24
          if score >=110
            score*=1.3
          end
        else
          thisinitial = score
          if thisinitial<100
            score*=0.5
            score*=0.5 if checkAIhealing(aimem)
          end
          if initialscores.length>0
            score*=0.3 if hasgreatmoves(initialscores,scoreindex,skill)
          end
          miniscore=100
          livecount=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount+=1 if i.hp!=0
          end
          if livecount>1
            miniscore*=(livecount-1)
            miniscore/=100.0
            miniscore*=0.1
            miniscore=(1-miniscore)
            score*=miniscore
          else
            score*=1.1
          end
          if @doublebattle
            score*=0.5
          end
          livecount2=0
          for i in pbParty(attacker.index)
            next if i.nil?
            livecount2+=1 if i.hp!=0
          end
          if livecount>1 && livecount2==1
            score*=0.7
          end
          if !@doublebattle
            if @opponent.trainertype==PBTrainers::ZEL
              score=thisinitial
              score *= 2
            end
          end
        end
      when 0xC3 # Razor Wind
        if !(attitemworks && attacker.item == PBItems::POWERHERB)
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=0.4
          else
            if attacker.hp*(1.0/attacker.totalhp)<0.5
              score*=0.6
            end
          end
          if opponent.effects[PBEffects::TwoTurnAttack]!=0
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=2
            else
              score*=0.5
            end
          end
          greatmove = false
          thisko = false
          if initialscores.length>0
            if initialscores[scoreindex] >= 100
              thisko = true
            end
            for i in initialscores
              if i>=100
                greatmove=true
              end
            end
          end
          if greatmove
            score*=0.1
          end
          if @doublebattle
            score*=0.5
          end
          score*=0.1 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
          if !thisko
            score*=0.7
          end
        else
          score*=1.2
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::UNBURDEN)
            score*=1.5
          end
        end
        fairyvar = false
        firevar = false
        poisonvar = false
        for p in pbParty(attacker.index)
          next if p.nil?
          fairyvar = true if p.hasType?(:FAIRY)
          firevar = true if p.hasType?(:FIRE)
          poisonvar = true if p.hasType?(:POISON)
        end
        if $fefieldeffect==3
          score*=1.3
          if !fairyvar
            score*=1.3
          else
            score*=0.6
          end
        elsif $fefieldeffect==7
          if !firevar
            score*=1.8
          else
            score*=0.5
          end
        elsif $fefieldeffect==11
          if !poisonvar
            score*=3
          else
            score*=0.8
          end
        end
      when 0xC4 # Solar Beam
        if !(attitemworks && attacker.item == PBItems::POWERHERB) && pbWeather!=PBWeather::SUNNYDAY
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=0.4
          else
            if attacker.hp*(1.0/attacker.totalhp)<0.5
              score*=0.6
            end
          end
          if opponent.effects[PBEffects::TwoTurnAttack]!=0
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=2
            else
              score*=0.5
            end
          end
          greatmove = false
          thisko = false
          if initialscores.length>0
            if initialscores[scoreindex] >= 100
              thisko = true
            end
            for i in initialscores
              if i>=100
                greatmove=true
              end
            end
          end
          if greatmove
            score*=0.1
          end
          if @doublebattle
            score*=0.5
          end
          score*=0.1 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
          if !thisko
            score*=0.7
          end
        else
          score*=1.2
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::UNBURDEN) && pbWeather!=PBWeather::SUNNYDAY
            score*=1.5
          end
        end
        if $fefieldeffect==4
          score*=0
        end
      when 0xC5 # Freeze Shock
        if !(attitemworks && attacker.item == PBItems::POWERHERB)
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=0.4
          else
            if attacker.hp*(1.0/attacker.totalhp)<0.5
              score*=0.6
            end
          end
          if opponent.effects[PBEffects::TwoTurnAttack]!=0
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=2
            else
              score*=0.5
            end
          end
          greatmove = false
          thisko = false
          if initialscores.length>0
            if initialscores[scoreindex] >= 100
              thisko = true
            end
            for i in initialscores
              if i>=100
                greatmove=true
              end
            end
          end
          if greatmove
            score*=0.1
          end
          if @doublebattle
            score*=0.5
          end
          score*=0.1 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
          if !thisko
            score*=0.7
          end
        else
          score*=1.2
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::UNBURDEN)
            score*=1.5
          end
        end
        if opponent.pbCanParalyze?(false)
          miniscore=100
          miniscore*=1.1
          miniscore*=1.3 if attacker.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
          if opponent.hp==opponent.totalhp
            miniscore*=1.2
          end
          ministat=0
          ministat+=opponent.stages[PBStats::ATTACK]
          ministat+=opponent.stages[PBStats::SPATK]
          ministat+=opponent.stages[PBStats::SPEED]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::NATURALCURE)
            miniscore*=0.3
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::MARVELSCALE)
            miniscore*=0.5
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::QUICKFEET) || (!opponent.abilitynulled && opponent.ability == PBAbilities::GUTS)
            miniscore*=0.2
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL) || roles.include?(PBMonRoles::PIVOT)
            miniscore*=1.2
          end
          if roles.include?(PBMonRoles::TANK)
            miniscore*=1.5
          end
          if pbRoughStat(opponent,PBStats::SPEED,skill)>attacker.pbSpeed && (pbRoughStat(opponent,PBStats::SPEED,skill)/2.0)<attacker.pbSpeed && @trickroom==0
            miniscore*=1.5
          end
          if pbRoughStat(opponent,PBStats::SPATK,skill)>pbRoughStat(opponent,PBStats::ATTACK,skill)
            miniscore*=1.3
          end
          count = -1
          sweepvar = false
          for i in pbParty(attacker.index)
            count+=1
            next if i.nil?
            temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
            if temprole.include?(PBMonRoles::SWEEPER)
              sweepvar = true
            end
          end
          miniscore*=1.3 if sweepvar
          if opponent.effects[PBEffects::Confusion]>0
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Attract]>=0
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SHEDSKIN)
            miniscore*=0.7
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
        end
      when 0xC6 # Ice Burn
        if !(attitemworks && attacker.item == PBItems::POWERHERB)
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=0.4
          else
            if attacker.hp*(1.0/attacker.totalhp)<0.5
              score*=0.6
            end
          end
          if opponent.effects[PBEffects::TwoTurnAttack]!=0
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=2
            else
              score*=0.5
            end
          end
          greatmove = false
          thisko = false
          if initialscores.length>0
            if initialscores[scoreindex] >= 100
              thisko = true
            end
            for i in initialscores
              if i>=100
                greatmove=true
              end
            end
          end
          if greatmove
            score*=0.1
          end
          if @doublebattle
            score*=0.5
          end
          score*=0.1 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
          if !thisko
            score*=0.7
          end
        else
          score*=1.2
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::UNBURDEN)
            score*=1.5
          end
        end
        if opponent.pbCanBurn?(false)
          miniscore=100
          miniscore*=1.2
          ministat=0
          ministat+=opponent.stages[PBStats::ATTACK]
          ministat+=opponent.stages[PBStats::SPATK]
          ministat+=opponent.stages[PBStats::SPEED]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::NATURALCURE)
            miniscore*=0.3
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::MARVELSCALE)
            miniscore*=0.7
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::QUICKFEET) || (!opponent.abilitynulled && opponent.ability == PBAbilities::FLAREBOOST) || (!opponent.abilitynulled && opponent.ability == PBAbilities::MAGICGUARD)
            miniscore*=0.3
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::GUTS)
            miniscore*=0.1
          end
          miniscore*=0.3 if checkAImoves([PBMoves::FACADE],aimem)
          miniscore*=0.1 if checkAImoves([PBMoves::REST],aimem)
          if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
            miniscore*=1.7
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SHEDSKIN)
            miniscore*=0.7
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
        end
      when 0xC7 # Sky Attack
        if !(attitemworks && attacker.item == PBItems::POWERHERB)
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=0.4
          else
            if attacker.hp*(1.0/attacker.totalhp)<0.5
              score*=0.6
            end
          end
          if opponent.effects[PBEffects::TwoTurnAttack]!=0
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=2
            else
              score*=0.5
            end
          end
          greatmove = false
          thisko = false
          if initialscores.length>0
            if initialscores[scoreindex] >= 100
              thisko = true
            end
            for i in initialscores
              if i>=100
                greatmove=true
              end
            end
          end
          if greatmove
            score*=0.1
          end
          if @doublebattle
            score*=0.5
          end
          score*=0.1 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
          if !thisko
            score*=0.7
          end
        else
          score*=1.2
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::UNBURDEN)
            score*=1.5
          end
        end
        if opponent.effects[PBEffects::Substitute]==0 && !(!opponent.abilitynulled && opponent.ability == PBAbilities::INNERFOCUS)
          if (pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed)   ^ (@trickroom!=0)
            miniscore=100
            miniscore*=1.3
            if skill>=PBTrainerAI.bestSkill
              if $fefieldeffect==14 # Rocky
                miniscore*=1.2
              end
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::STEADFAST)
              miniscore*=0.3
            end
            miniscore-=100
            if move.addlEffect.to_f != 100
              miniscore*=(move.addlEffect.to_f/100)
              if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
                miniscore*=2
              end
            end
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
        end
      when 0xC8 # Skull Bash
        if !(attitemworks && attacker.item == PBItems::POWERHERB)
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=0.4
          else
            if attacker.hp*(1.0/attacker.totalhp)<0.5
              score*=0.6
            end
          end
          if opponent.effects[PBEffects::TwoTurnAttack]!=0
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=2
            else
              score*=0.5
            end
          end
          greatmove = false
          thisko = false
          if initialscores.length>0
            if initialscores[scoreindex] >= 100
              thisko = true
            end
            for i in initialscores
              if i>=100
                greatmove=true
              end
            end
          end
          if greatmove
            score*=0.1
          end
          if @doublebattle
            score*=0.5
          end
          score*=0.1 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
          if !thisko
            score*=0.7
          end
        else
          score*=1.2
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::UNBURDEN)
            score*=1.5
          end
        end
        miniscore=100
        if attacker.effects[PBEffects::Substitute]>0 || attacker.effects[PBEffects::Disguise]
          miniscore*=1.3
        end
        if (attacker.hp.to_f)/attacker.totalhp>0.75
          miniscore*=1.1
        end
        if opponent.effects[PBEffects::HyperBeam]>0
          miniscore*=1.2
        end
        if opponent.effects[PBEffects::Yawn]>0
          miniscore*=1.3
        end
        if skill>=PBTrainerAI.mediumSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if maxdam<(attacker.hp/3.0) && (aimem.length > 0)
            miniscore*=1.1
          end
        end
        if attacker.turncount<2
          miniscore*=1.1
        end
        if opponent.status!=0
          miniscore*=1.1
        end
        if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
          miniscore*=1.3
        end
        if opponent.effects[PBEffects::Encore]>0
          if opponent.moves[(opponent.effects[PBEffects::EncoreIndex])].basedamage==0
            miniscore*=1.3
          end
        end
        if attacker.effects[PBEffects::Confusion]>0
          miniscore*=0.3
        end
        if attacker.effects[PBEffects::LeechSeed]>=0 || attacker.effects[PBEffects::Attract]>=0
          miniscore*=0.3
        end
        if attacker.effects[PBEffects::Toxic]>0
          miniscore*=0.2
        end
        miniscore*=0.2 if checkAImoves(PBStuff::SWITCHOUTMOVE,aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SIMPLE)
          miniscore*=2
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=0.5
        end
        if @doublebattle
          miniscore*=0.3
        end
        if attacker.stages[PBStats::DEFENSE]>0
          ministat=attacker.stages[PBStats::DEFENSE]
          minimini=-15*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
          miniscore*=1.3
        end
        if skill>=PBTrainerAI.mediumSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if (maxdam.to_f/attacker.hp)<0.12 && (aimem.length > 0)
            miniscore*=0.3
          end
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        miniscore-=100
        if move.addlEffect.to_f != 100
          miniscore*=(move.addlEffect.to_f/100)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
            miniscore*=2
          end
        end
        miniscore+=100
        miniscore/=100.0
        if attacker.pbTooHigh?(PBStats::DEFENSE)
          miniscore=1
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          miniscore*=0.5
        end
        score*=miniscore
      when 0xC9 # Fly
        livecount1=0
        for i in pbParty(opponent.index)
          next if i.nil?
          livecount1+=1 if i.hp!=0
        end
        livecount2=0
        for i in pbParty(attacker.index)
          next if i.nil?
          livecount2+=1 if i.hp!=0
        end
        if skill<PBTrainerAI.bestSkill || $fefieldeffect!=23 # Not in a cave
          if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::MultiTurn]>0 || opponent.effects[PBEffects::Curse]
            score*=1.2
          else
            if livecount1>1
              score*=0.8
            end
          end
          if attacker.status!=0 || attacker.effects[PBEffects::Curse] || attacker.effects[PBEffects::Attract]>-1 || attacker.effects[PBEffects::Confusion]>0
            score*=0.5
          end
          if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
            score*=1.1
          end
          if attacker.pbOwnSide.effects[PBEffects::Tailwind]>0 || attacker.pbOwnSide.effects[PBEffects::Reflect]>0 || attacker.pbOwnSide.effects[PBEffects::LightScreen]>0
            score*=0.7
          end
          if opponent.effects[PBEffects::PerishSong]!=0 && attacker.effects[PBEffects::PerishSong]==0
            score*=1.3
          end
          if (attitemworks && attacker.item == PBItems::POWERHERB)
            score*=1.5
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD) || (!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD)
            score*=0.1
          end
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            if opponent.vanished
              score*=3
            end
            score*=1.1
          else
            score*=0.8
            score*=0.5 if checkAIhealing(aimem)
            score*=0.7 if checkAIaccuracy(aimem)
          end
          score*=0.3 if checkAImoves([PBMoves::THUNDER,PBMoves::HURRICANE],aimem)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==22
              if !attacker.pbHasType?(PBTypes::WATER)
                score*=2
              end
            end
          end
        end
        if @field.effects[PBEffects::Gravity]>0
          score*=0
        end
      when 0xCA # Dig
        livecount1=0
        for i in pbParty(opponent.index)
          next if i.nil?
          livecount1+=1 if i.hp!=0
        end
        livecount2=0
        for i in pbParty(attacker.index)
          next if i.nil?
          livecount2+=1 if i.hp!=0
        end
        if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::MultiTurn]>0 || opponent.effects[PBEffects::Curse]
          score*=1.2
        else
          if livecount1>1
            score*=0.8
          end
        end
        if attacker.status!=0 || attacker.effects[PBEffects::Curse] || attacker.effects[PBEffects::Attract]>-1 || attacker.effects[PBEffects::Confusion]>0
          score*=0.5
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          score*=1.1
        end
        if attacker.pbOwnSide.effects[PBEffects::Tailwind]>0 || attacker.pbOwnSide.effects[PBEffects::Reflect]>0 || attacker.pbOwnSide.effects[PBEffects::LightScreen]>0
          score*=0.7
        end
        if opponent.effects[PBEffects::PerishSong]!=0 && attacker.effects[PBEffects::PerishSong]==0
          score*=1.3
        end
        if (attitemworks && attacker.item == PBItems::POWERHERB)
          score*=1.5
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD) || (!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD)
          score*=0.1
        end
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          if opponent.vanished
            score*=3
          end
          score*=1.1
        else
          score*=0.8
          score*=0.5 if checkAIhealing(aimem)
          score*=0.7 if checkAIaccuracy(aimem)
        end
        score*=0.3 if checkAImoves([PBMoves::EARTHQUAKE],aimem)
      when 0xCB # Dive
        livecount1=0
        for i in pbParty(opponent.index)
          next if i.nil?
          livecount1+=1 if i.hp!=0
        end
        livecount2=0
        for i in pbParty(attacker.index)
          next if i.nil?
          livecount2+=1 if i.hp!=0
        end
        if skill>=PBTrainerAI.bestSkill && ($fefieldeffect==21 || $fefieldeffect==22)  # Water Surface/Underwater
          if $fefieldeffect==21 # Water Surface
            if !opponent.pbHasType?(PBTypes::WATER)
              score*=2
            else
              for mon in pbParty(attacker.index)
                watervar=false
                next if mon.nil?
                if mon.hasType?(:WATER)
                  watervar=true
                end
                if watervar
                  score*=1.3
                end
              end
            end
          else
            if !attacker.pbHasType?(PBTypes::WATER)
              score*=2
            else
              for mon in pbParty(attacker.index)
                watervar=false
                next if mon.nil?
                if mon.hasType?(:WATER)
                  watervar=true
                end
                if watervar
                  score*=0.6
                end
              end
            end
          end
        else
          if $fefieldeffect==26 # Murkwater Surface
            if !attacker.pbHasType?(PBTypes::POISON) && !attacker.pbHasType?(PBTypes::STEEL)
              score*=0.3
            end
          end
          if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::MultiTurn]>0 || opponent.effects[PBEffects::Curse]
            score*=1.2
          else
            if livecount1>1
              score*=0.8
            end
          end
          if attacker.status!=0 || attacker.effects[PBEffects::Curse] || attacker.effects[PBEffects::Attract]>-1 || attacker.effects[PBEffects::Confusion]>0
            score*=0.5
          end
          if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
            score*=1.1
          end
          if attacker.pbOwnSide.effects[PBEffects::Tailwind]>0 || attacker.pbOwnSide.effects[PBEffects::Reflect]>0 || attacker.pbOwnSide.effects[PBEffects::LightScreen]>0
            score*=0.7
          end
          if opponent.effects[PBEffects::PerishSong]!=0 && attacker.effects[PBEffects::PerishSong]==0
            score*=1.3
          end
          if (attitemworks && attacker.item == PBItems::POWERHERB)
            score*=1.5
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD) || (!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD)
            score*=0.1
          end
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            if opponent.vanished
              score*=3
            end
            score*=1.1
          else
            score*=0.8
            score*=0.5 if checkAIhealing(aimem)
            score*=0.7 if checkAIaccuracy(aimem)
          end
          score*=0.3 if checkAImoves([PBMoves::SURF],aimem)
        end
      when 0xCC # Bounce
        if opponent.pbCanParalyze?(false)
          miniscore=100
          miniscore*=1.1 if attacker.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
          if opponent.hp==opponent.totalhp
            miniscore*=1.2
          end
          ministat=0
          ministat+=opponent.stages[PBStats::ATTACK]
          ministat+=opponent.stages[PBStats::SPATK]
          ministat+=opponent.stages[PBStats::SPEED]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::NATURALCURE)
            miniscore*=0.3
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::MARVELSCALE)
            miniscore*=0.5
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::QUICKFEET) || (!opponent.abilitynulled && opponent.ability == PBAbilities::GUTS)
            miniscore*=0.2
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL) || roles.include?(PBMonRoles::PIVOT)
            miniscore*=1.2
          end
          if roles.include?(PBMonRoles::TANK)
            miniscore*=1.3
          end
          if pbRoughStat(opponent,PBStats::SPEED,skill)>attacker.pbSpeed && (pbRoughStat(opponent,PBStats::SPEED,skill)/2)<attacker.pbSpeed && @trickroom==0
            miniscore*=1.5
          end
          if pbRoughStat(opponent,PBStats::SPATK,skill)>pbRoughStat(opponent,PBStats::ATTACK,skill)
            miniscore*=1.1
          end
          count = -1
          sweepvar = false
          for i in pbParty(attacker.index)
            count+=1
            next if i.nil?
            temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
            if temprole.include?(PBMonRoles::SWEEPER)
              sweepvar = true
            end
          end
          miniscore*=1.1 if sweepvar
          if opponent.effects[PBEffects::Confusion]>0
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Attract]>=0
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SHEDSKIN)
            miniscore*=0.7
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
        end
        livecount1=0
        for i in pbParty(opponent.index)
          next if i.nil?
          livecount1+=1 if i.hp!=0
        end
        livecount2=0
        for i in pbParty(attacker.index)
          next if i.nil?
          livecount2+=1 if i.hp!=0
        end
        if skill<PBTrainerAI.bestSkill || $fefieldeffect!=23 # Not in a cave
          if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::MultiTurn]>0 || opponent.effects[PBEffects::Curse]
            score*=1.2
          else
            if livecount1>1
              score*=0.7
            end
          end
          if attacker.status!=0 || attacker.effects[PBEffects::Curse] || attacker.effects[PBEffects::Attract]>-1 || attacker.effects[PBEffects::Confusion]>0
            score*=0.5
          end
          if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
            score*=1.1
          end
          if attacker.pbOwnSide.effects[PBEffects::Tailwind]>0 || attacker.pbOwnSide.effects[PBEffects::Reflect]>0 || attacker.pbOwnSide.effects[PBEffects::LightScreen]>0
            score*=0.7
          end
          if opponent.effects[PBEffects::PerishSong]!=0 && attacker.effects[PBEffects::PerishSong]==0
            score*=1.3
          end
          if (attitemworks && attacker.item == PBItems::POWERHERB)
            score*=1.5
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD) || (!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD)
            score*=0.1
          end
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            if opponent.vanished
              score*=3
            end
            score*=1.1
          else
            score*=0.8
            score*=0.5 if checkAIhealing(aimem)
            score*=0.7 if checkAIaccuracy(aimem)
          end
          score*=0.3 if checkAImoves([PBMoves::THUNDER,PBMoves::HURRICANE],aimem)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==22
              if !attacker.pbHasType?(PBTypes::WATER)
                score*=2
              end
            end
          end
        end
        if @field.effects[PBEffects::Gravity]>0
          score*=0
        end
      when 0xCD # Phantom Force
        livecount1=0
        for i in pbParty(opponent.index)
          next if i.nil?
          livecount1+=1 if i.hp!=0
        end
        livecount2=0
        for i in pbParty(attacker.index)
          next if i.nil?
          livecount2+=1 if i.hp!=0
        end
        if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::MultiTurn]>0 || opponent.effects[PBEffects::Curse]
          score*=1.2
        else
          if livecount1>1
            score*=0.8
          end
        end
        if attacker.status!=0 || attacker.effects[PBEffects::Curse] || attacker.effects[PBEffects::Attract]>-1 || attacker.effects[PBEffects::Confusion]>0
          score*=0.5
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          score*=1.1
        end
        if attacker.pbOwnSide.effects[PBEffects::Tailwind]>0 || attacker.pbOwnSide.effects[PBEffects::Reflect]>0 || attacker.pbOwnSide.effects[PBEffects::LightScreen]>0
          score*=0.7
        end
        if opponent.effects[PBEffects::PerishSong]!=0 && attacker.effects[PBEffects::PerishSong]==0
          score*=1.3
        end
        if (attitemworks && attacker.item == PBItems::POWERHERB)
          score*=1.5
        end
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=1.1
        else
          score*=0.8
          score*=0.5 if checkAIhealing(aimem)
          score*=0.7 if checkAIaccuracy(aimem)
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD) || (!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD)
          score*=0.1
        else
          miniscore=100
          if attacker.stages[PBStats::ACCURACY]<0
            miniscore = (-5)*attacker.stages[PBStats::ACCURACY]
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
          if opponent.stages[PBStats::EVASION]>0
            miniscore = (5)*opponent.stages[PBStats::EVASION]
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
          if (oppitemworks && opponent.item == PBItems::LAXINCENSE) || (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER)
            score*=1.2
          end
          if ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) || ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL)
            score*=1.3
          end
          if opponent.vanished && ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0))
            score*=3
          end
        end
      when 0xCE # Sky Drop
        if opponent.pbHasType?(:FLYING)
          score = 5
        end
        livecount1=0
        for i in pbParty(opponent.index)
          next if i.nil?
          livecount1+=1 if i.hp!=0
        end
        livecount2=0
        for i in pbParty(attacker.index)
          next if i.nil?
          livecount2+=1 if i.hp!=0
        end
        if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::MultiTurn]>0 || opponent.effects[PBEffects::Curse]
          score*=1.5
        else
          if livecount1>1
            score*=0.8
          end
        end
        if attacker.status!=0 || attacker.effects[PBEffects::Curse] || attacker.effects[PBEffects::Attract]>-1 || attacker.effects[PBEffects::Confusion]>0
          score*=0.5
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          score*=1.1
        end
        if attacker.pbOwnSide.effects[PBEffects::Tailwind]>0 || attacker.pbOwnSide.effects[PBEffects::Reflect]>0 || attacker.pbOwnSide.effects[PBEffects::LightScreen]>0
          score*=0.7
        end
        if opponent.effects[PBEffects::PerishSong]!=0 && attacker.effects[PBEffects::PerishSong]==0
          score*=1.3
        end
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill))  ^ (@trickroom!=0)
          score*=1.1
        else
          score*=0.8
        end
        if $fefieldeffect==22
          if !attacker.pbHasType?(:WATER)
            score*=2
          end
        end
        if @field.effects[PBEffects::Gravity]>0 || $fefieldeffect==23 || opponent.effects[PBEffects::Substitute]>0
          score*=0
        end
      when 0xCF # Fire Spin
        if opponent.effects[PBEffects::MultiTurn]==0 && opponent.effects[PBEffects::Substitute]<=0
          score*=1.2
          if initialscores.length>0
            score*=1.2 if hasbadmoves(initialscores,scoreindex,30)
          end
          ministat=(-5)*statchangecounter(opponent,1,7,1)
          ministat+=100
          ministat/=100.0
          score*=ministat
          if opponent.totalhp == opponent.hp
            score*=1.2
          elsif opponent.hp*2 < opponent.totalhp
            score*=0.8
          end
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=0.7
          elsif attacker.hp*3<attacker.totalhp
            score*=0.7
          end
          if opponent.effects[PBEffects::LeechSeed]>=0
            score*=1.5
          end
          if opponent.effects[PBEffects::Attract]>-1
            score*=1.3
          end
          if opponent.effects[PBEffects::Confusion]>0
            score*=1.3
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            score*=1.2
          end
          movecheck = false
          for j in attacker.moves
            movecheck = true if j.id==(PBMoves::PROTECT) || j.id==(PBMoves::DETECT) || j.id==(PBMoves::BANEFULBUNKER) || j.id==(PBMoves::SPIKYSHIELD)
          end
          if movecheck
            score*=1.1
          end
          if (attitemworks && attacker.item == PBItems::BINDINGBAND)
            score*=1.3
          end
          if (attitemworks && attacker.item == PBItems::GRIPCLAW)
            score*=1.1
          end
        end
        if move.id==(PBMoves::FIRESPIN)
          if $fefieldeffect==20
            score*=0.7
          end
        end
        if move.id==(PBMoves::MAGMASTORM)
          if $fefieldeffect==32
            score*=1.3
          end
        end
        if move.id==(PBMoves::SANDTOMB)
          if $fefieldeffect==12
            score*=1.3
          elsif $fefieldeffect==20
            score*=1.5 unless opponent.stages[PBStats::ACCURACY]<(-2)
          end
        end
        if move.id==(PBMoves::INFESTATION)
          if $fefieldeffect==15
            score*=1.3
          elsif $fefieldeffect==33
            score*=1.3
            if $fecounter == 3
              score*=1.3
            end
            if $fecounter == 4
              score*=1.5
            end
          end
        end
      when 0xD0 # Whirlpool
        if opponent.effects[PBEffects::MultiTurn]==0 && opponent.effects[PBEffects::Substitute]<=0
          score*=1.2
          if initialscores.length>0
            score*=1.2 if hasbadmoves(initialscores,scoreindex,30)
          end
          ministat=(-5)*statchangecounter(opponent,1,7,1)
          ministat+=100
          ministat/=100.0
          score*=ministat
          if opponent.totalhp == opponent.hp
            score*=1.2
          elsif opponent.hp*2 < opponent.totalhp
            score*=0.8
          end
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=0.7
          elsif attacker.hp*3<attacker.totalhp
            score*=0.7
          end
          if opponent.effects[PBEffects::LeechSeed]>=0
            score*=1.5
          end
          if opponent.effects[PBEffects::Attract]>-1
            score*=1.3
          end
          if opponent.effects[PBEffects::Confusion]>0
            score*=1.3
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            score*=1.2
          end
          movecheck = false
          for j in attacker.moves
            movecheck = true if j.id==(PBMoves::PROTECT) || j.id==(PBMoves::DETECT) || j.id==(PBMoves::BANEFULBUNKER) || j.id==(PBMoves::SPIKYSHIELD)
          end
          if movecheck
            score*=1.1
          end
          if (attitemworks && attacker.item == PBItems::BINDINGBAND)
            score*=1.3
          end
          if (attitemworks && attacker.item == PBItems::GRIPCLAW)
            score*=1.1
          end
          if $pkmn_move[opponent.effects[PBEffects::TwoTurnAttack]][0] #the function code of the current move==0xCB
            score*=1.3
          end
        end
        watervar = false
        poisonvar = false
        for p in pbParty(attacker.index)
          next if p.nil?
          watervar = true if p.hasType?(:WATER)
          poisonvar = true if p.hasType?(:POISON)
        end
        if $fefieldeffect==20
          score*=0.7
        end
        if $fefieldeffect==21 || $fefieldeffect==22
          score*=1.3
          if opponent.effects[PBEffects::Confusion]<=0
            score*=1.5
          end
        end
        if $fefieldeffect==26
          if score==0
            score+=10
          end
          if !(attacker.pbHasType?(:POISON) || attacker.pbHasType?(:STEEL))
            score*=1.5
          end
          if !poisonvar
            score*=2
          end
          if watervar
            score*=2
          end
        end
      when 0xD1 # Uproar
        if opponent.status==PBStatuses::SLEEP
          score*=0.7
        end
        if opponent.pbHasMove?((PBMoves::REST))
          score*=1.8
        end
        if opponent.pbNonActivePokemonCount==0 || (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || opponent.effects[PBEffects::MeanLook]>0
          score*=1.1
        end
        typemod=move.pbTypeModifier(move.type,attacker,opponent)
        if typemod<4
          score*=0.7
        end
        if attacker.hp*(1.0/attacker.totalhp)<0.75
          score*=0.75
        end
        if attacker.stages[PBStats::SPATK]<0
          minimini = attacker.stages[PBStats::SPATK]
          minimini*=5
          minimini+=100
          minimini/=100.0
          score*=minimini
        end
        if opponent.pbNonActivePokemonCount>1
          miniscore = opponent.pbNonActivePokemonCount*0.05
          miniscore = 1-miniscore
          score*=miniscore
        end
      when 0xD2 # Outrage
        livecount1=0
        thisinitial = score
        for i in pbParty(opponent.index)
          next if i.nil?
          livecount1+=1 if i.hp!=0
        end
        #this isn't used?
        #livecount2=0
        #for i in pbParty(attacker.index)
        #  next if i.nil?
        #  livecount2+=1 if i.hp!=0
        #end
        if !(!attacker.abilitynulled && attacker.ability == PBAbilities::OWNTEMPO)
          if thisinitial<100
            score*=0.85
          end
          if (attitemworks && attacker.item == PBItems::LUMBERRY) || (attitemworks && attacker.item == PBItems::PERSIMBERRY)
            score*=1.3
          end
          if attacker.stages[PBStats::ATTACK]>0
            miniscore = (-5)*attacker.stages[PBStats::ATTACK]
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
          if livecount1>2
            miniscore=100
            miniscore*=(livecount1-1)
            miniscore*=0.01
            miniscore*=0.025
            miniscore=1-miniscore
            score*=miniscore
          end
          score*=0.7 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
          score*=0.7 if checkAIhealing(aimem)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==16 # Superheated Field
              score*=0.5
            end
          end
        else
            score *= 1.2
        end
        if move.id==(PBMoves::PETALDANCE)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==33 && $fecounter>1
              score*=1.5
            end
          end
        elsif move.id==(PBMoves::OUTRAGE)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect!=36
              fairyvar = false
              for mon in pbParty(opponent.index)
                next if mon.nil?
                ghostvar=true if mon.hasType?(:FAIRY)
              end
              if fairyvar
                score*=0.8
              end
            end
          end
        elsif move.id==(PBMoves::THRASH)
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect!=36
              ghostvar = false
              for mon in pbParty(opponent.index)
                next if mon.nil?
                ghostvar=true if mon.hasType?(:GHOST)
              end
              if ghostvar
                score*=0.8
              end
            end
          end
        end
      when 0xD3 # Rollout
        if opponent.pbNonActivePokemonCount==0 || (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || opponent.effects[PBEffects::MeanLook]>0
          score*=1.1
        end
        if attacker.hp*(1.0/attacker.totalhp)<0.75
          score*=0.75
        end
        if attacker.stages[PBStats::ACCURACY]<0
            miniscore = (5)*attacker.stages[PBStats::ATTACK]
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
          if attacker.stages[PBStats::ATTACK]<0
            miniscore = (5)*attacker.stages[PBStats::ATTACK]
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
          if opponent.stages[PBStats::EVASION]>0
            miniscore = (-5)*attacker.stages[PBStats::ATTACK]
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
          if (oppitemworks && opponent.item == PBItems::LAXINCENSE) || (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER)
            score*=0.8
          end
          if ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) || ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL)
            score*=0.8
          end
          if attacker.status==PBStatuses::PARALYSIS
            score*=0.5
          end
          if attacker.effects[PBEffects::Confusion]>0
            score*=0.5
          end
          if attacker.effects[PBEffects::Attract]>=0
            score*=0.5
          end
          if opponent.pbNonActivePokemonCount>1
            miniscore = 1 - (opponent.pbNonActivePokemonCount*0.05)
            score*=miniscore
          end
          if attacker.effects[PBEffects::DefenseCurl]
            score*=1.2
          end
          if checkAIdamage(aimem,attacker,opponent,skill)*3<attacker.hp && (aimem.length > 0)
            score*=1.5
          end
          score*=0.8 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
          if $fefieldeffect==13
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=1.3
            end
          end
      when 0xD4 # Bide
        statmove = false
        movelength = -1
        if aimem.length > 0
          for j in aimem
            movelength = aimem.length
            if j.basedamage==0
              statmove=true
            end
          end
        end
        if ((attitemworks && attacker.item == PBItems::FOCUSSASH) || (!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY))
          score*=1.2
        end
        miniscore = attacker.hp*(1.0/attacker.totalhp)
        score*=miniscore
        if checkAIdamage(aimem,attacker,opponent,skill)*2 > attacker.hp
          score*=0.2
        end
        if attacker.hp*3<attacker.totalhp
          score*=0.7
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          score*=1.1
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          score*=1.3
        end
        if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=1.3
        end
        score*=0.5 if checkAImoves(PBStuff::SETUPMOVE,aimem)
        if statmove
          score*=0.8
        else
          if movelength==4
            score*=1.3
          end
        end
      when 0xD5 # Recover
        if aimem.length > 0 && skill>=PBTrainerAI.bestSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if maxdam>attacker.hp
            if maxdam>(attacker.hp*1.5)
              score=0
            else
              score*=5
            #experimental -- cancels out drop if killing moves
              if initialscores.length>0
                score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
              end
              #end experimental
            end
          else
            if maxdam*1.5>attacker.hp
              score*=2
            end
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              if maxdam*2>attacker.hp
                score*=5
                #experimental -- cancels out drop if killing moves
                if initialscores.length>0
                  score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
                end
                #end experimental
              end
            end
          end
        elsif skill>=PBTrainerAI.bestSkill #no highest expected damage yet
          if ((attacker.hp.to_f)/attacker.totalhp)<0.5
            score*=3
            if ((attacker.hp.to_f)/attacker.totalhp)<0.25
              score*=3
            end
            #experimental -- cancels out drop if killing moves
            if initialscores.length>0
              score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
            end
            #end experimental
          end
        elsif skill>=PBTrainerAI.mediumSkill
          score*=3 if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
        end
        score*=0.7 if opponent.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
        if (attacker.hp.to_f)/attacker.totalhp<0.5
          score*=1.5
          if attacker.effects[PBEffects::Curse]
            score*=2
          end
          if attacker.hp*4<attacker.totalhp
            if attacker.status==PBStatuses::POISON
              score*=1.5
            end
            if attacker.effects[PBEffects::LeechSeed]>=0
              score*=2
            end
            if attacker.hp<attacker.totalhp*0.13
              if attacker.status==PBStatuses::BURN
                score*=2
              end
              if (pbWeather==PBWeather::HAIL && !attacker.pbHasType?(:ICE)) || (pbWeather==PBWeather::SANDSTORM && !attacker.pbHasType?(:ROCK) && !attacker.pbHasType?(:GROUND) && !attacker.pbHasType?(:STEEL))
                score*=2
              end
            end
          end
        else
          score*=0.9
        end
        if attacker.effects[PBEffects::Toxic]>0
          score*=0.5
          if attacker.effects[PBEffects::Toxic]>4
            score*=0.5
          end
        end
        if attacker.status==PBStatuses::PARALYSIS || attacker.effects[PBEffects::Attract]>=0 || attacker.effects[PBEffects::Confusion]>0
          score*=1.1
        end
        if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::Curse]
          score*=1.3
          if opponent.effects[PBEffects::Toxic]>0
            score*=1.3
          end
        end
        score*=1.3 if checkAImoves(PBStuff::CONTRARYBAITMOVE,aimem)
        if opponent.vanished || opponent.effects[PBEffects::HyperBeam]>0
          score*=1.2
        end
        if skill>=PBTrainerAI.bestSkill
          if move.id==(PBMoves::HEALORDER)
            if $fefieldeffect==15 # Forest
              score*=1.3
            end
          end
        end
        if ((attacker.hp.to_f)/attacker.totalhp)>0.8
          score=0
        elsif ((attacker.hp.to_f)/attacker.totalhp)>0.6
          score*=0.6
        elsif ((attacker.hp.to_f)/attacker.totalhp)<0.25
          score*=2
        end
        if attacker.effects[PBEffects::Wish]>0
            score=0
        end
      when 0xD6 # Roost
        besttype=-1
        if aimem.length > 0 && skill>=PBTrainerAI.bestSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if maxdam>attacker.hp
            if maxdam>(attacker.hp*1.5)
              score=0
            else
              score*=5
            #experimental -- cancels out drop if killing moves
              if initialscores.length>0
                score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
              end
              #end experimental
            end
          else
            if maxdam*1.5>attacker.hp
              score*=2
            end
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              if maxdam*2>attacker.hp
                score*=5
                #experimental -- cancels out drop if killing moves
                if initialscores.length>0
                  score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
                end
                #end experimental
              end
            end
          end
        elsif skill>=PBTrainerAI.bestSkill #no highest expected damage yet
          if ((attacker.hp.to_f)/attacker.totalhp)<0.5
            score*=3
            if ((attacker.hp.to_f)/attacker.totalhp)<0.25
              score*=3
            end
            #experimental -- cancels out drop if killing moves
            if initialscores.length>0
              score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
            end
            #end experimental
          end
        elsif skill>=PBTrainerAI.mediumSkill
          score*=3 if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
        end
        score*=0.7 if opponent.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
        if (attacker.hp.to_f)/attacker.totalhp<0.5
          score*=1.5
          if attacker.effects[PBEffects::Curse]
            score*=2
          end
          if attacker.hp*4<attacker.totalhp
            if attacker.status==PBStatuses::POISON
              score*=1.5
            end
            if attacker.effects[PBEffects::LeechSeed]>=0
              score*=2
            end
            if attacker.hp<attacker.totalhp*0.13
              if attacker.status==PBStatuses::BURN
                score*=2
              end
              if (pbWeather==PBWeather::HAIL && !attacker.pbHasType?(:ICE)) || (pbWeather==PBWeather::SANDSTORM && !attacker.pbHasType?(:ROCK) && !attacker.pbHasType?(:GROUND) && !attacker.pbHasType?(:STEEL))
                score*=2
              end
            end
          end
        else
          score*=0.9
        end
        if attacker.effects[PBEffects::Toxic]>0
          score*=0.5
          if attacker.effects[PBEffects::Toxic]>4
            score*=0.5
          end
        end
        if attacker.status==PBStatuses::PARALYSIS || attacker.effects[PBEffects::Attract]>=0 || attacker.effects[PBEffects::Confusion]>0
          score*=1.1
        end
        #if !(roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL))
        #  score*=0.8
        #end
        if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::Curse]
          score*=1.3
          if opponent.effects[PBEffects::Toxic]>0
            score*=1.3
          end
        end
        score*=1.3 if checkAImoves(PBStuff::CONTRARYBAITMOVE,aimem)
        if opponent.vanished || opponent.effects[PBEffects::HyperBeam]>0
          score*=1.2
        end
        if besttype!=-1
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            if (m.type == PBTypes::ROCK) || (m.type == PBTypes::ICE) || (m.type == PBTypes::ELECTRIC)
              score*=1.5
            else
              if (m.type == PBTypes::BUG) || (m.type == PBTypes::FIGHTING) || (m.type == PBTypes::GRASS) || (m.type == PBTypes::GROUND)
                score*=0.5
              end
            end
          end
        end
        if ((attacker.hp.to_f)/attacker.totalhp)>0.8
          score=0
        elsif ((attacker.hp.to_f)/attacker.totalhp)>0.6
          score*=0.6
        elsif ((attacker.hp.to_f)/attacker.totalhp)<0.25
          score*=2
        end
        if attacker.effects[PBEffects::Wish]>0
            score=0
        end
      when 0xD7 # Wish
        protectmove=false
        for j in attacker.moves
          protectmove = true if j.id==(PBMoves::PROTECT) || j.id==(PBMoves::DETECT) || j.id==(PBMoves::BANEFULBUNKER) || j.id==(PBMoves::SPIKYSHIELD)
        end
        if aimem.length > 0 && skill>=PBTrainerAI.bestSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if maxdam>attacker.hp
            if maxdam>(attacker.hp*1.5)
              score=0
            else
              score*=5
            #experimental -- cancels out drop if killing moves
              if initialscores.length>0
                score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
              end
              #end experimental
            end
          else
            if maxdam*1.5>attacker.hp
              score*=2
            end
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              if maxdam*2>attacker.hp
                score*=5
                #experimental -- cancels out drop if killing moves
                if initialscores.length>0
                  score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
                end
                #end experimental
              end
            end
          end
        elsif skill>=PBTrainerAI.bestSkill #no highest expected damage yet
          if ((attacker.hp.to_f)/attacker.totalhp)<0.5
            score*=3
            if ((attacker.hp.to_f)/attacker.totalhp)<0.25
              score*=3
            end
            #experimental -- cancels out drop if killing moves
            if initialscores.length>0
              score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
            end
            #end experimental
          end
        elsif skill>=PBTrainerAI.mediumSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if maxdam>attacker.hp
            score*=3
          end
        end
        score*=0.7 if opponent.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
        if (attacker.hp.to_f)/attacker.totalhp<0.5
          if attacker.effects[PBEffects::Curse]
            score*=2
          end
          if attacker.hp*4<attacker.totalhp
            if attacker.status==PBStatuses::POISON
              score*=1.5
            end
            if attacker.effects[PBEffects::LeechSeed]>=0
              score*=2
            end
            if attacker.hp<attacker.totalhp*0.13
              if attacker.status==PBStatuses::BURN
                score*=2
              end
              if (pbWeather==PBWeather::HAIL && !attacker.pbHasType?(:ICE)) || (pbWeather==PBWeather::SANDSTORM && !attacker.pbHasType?(:ROCK) && !attacker.pbHasType?(:GROUND) && !attacker.pbHasType?(:STEEL))
                score*=2
              end
            end
          end
        else
          score*=0.7
        end
        if attacker.effects[PBEffects::Toxic]>0
          score*=0.5
          if attacker.effects[PBEffects::Toxic]>4
            score*=0.5
          end
        end
        if attacker.status==PBStatuses::PARALYSIS || attacker.effects[PBEffects::Attract]>=0 || attacker.effects[PBEffects::Confusion]>0
          score*=1.1
        end
        if !(roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL))
          score*=0.8
        end
        if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::Curse]
          score*=1.3
          if opponent.effects[PBEffects::Toxic]>0
            score*=1.3
          end
        end
        score*=1.3 if checkAImoves(PBStuff::CONTRARYBAITMOVE,aimem)
        if opponent.vanished || opponent.effects[PBEffects::HyperBeam]>0
          score*=1.2
        end
        if roles.include?(PBMonRoles::CLERIC)
          wishpass=false
          for i in pbParty(attacker.index)
            next if i.nil?
            if (i.hp.to_f)/(i.totalhp.to_f)<0.6 && (i.hp.to_f)/(i.totalhp.to_f)>0.3
              wishpass=true
            end
          end
          score*=1.3 if wishpass
        end
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==3 || $fefieldeffect==9 || $fefieldeffect==29 || $fefieldeffect==31 || $fefieldeffect==34 # Misty/Rainbow/Holy/Fairytale/Starlight
            score*=1.5
          end
        end
        if attacker.effects[PBEffects::Wish]>0
          score=0
        end
      when 0xD8 # Synthesis
        if aimem.length > 0 && skill>=PBTrainerAI.bestSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if maxdam>attacker.hp
            if maxdam>(attacker.hp*1.5)
              score=0
            else
              score*=5
            #experimental -- cancels out drop if killing moves
              if initialscores.length>0
                score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
              end
              #end experimental
            end
          else
            if maxdam*1.5>attacker.hp
              score*=2
            end
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              if maxdam*2>attacker.hp
                score*=5
                #experimental -- cancels out drop if killing moves
                if initialscores.length>0
                  score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
                end
                #end experimental
              end
            end
          end
        elsif skill>=PBTrainerAI.bestSkill #no highest expected damage yet
          if ((attacker.hp.to_f)/attacker.totalhp)<0.5
            score*=3
            if ((attacker.hp.to_f)/attacker.totalhp)<0.25
              score*=3
            end
            #experimental -- cancels out drop if killing moves
            if initialscores.length>0
              score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
            end
            #end experimental
          end
        elsif skill>=PBTrainerAI.mediumSkill
          score*=3 if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
        end
        score*=0.7 if opponent.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
        if (attacker.hp.to_f)/attacker.totalhp<0.5
          score*=1.5
          if attacker.effects[PBEffects::Curse]
            score*=2
          end
          if attacker.hp*4<attacker.totalhp
            if attacker.status==PBStatuses::POISON
              score*=1.5
            end
            if attacker.effects[PBEffects::LeechSeed]>=0
              score*=2
            end
            if attacker.hp<attacker.totalhp*0.13
              if attacker.status==PBStatuses::BURN
                score*=2
              end
              if (pbWeather==PBWeather::HAIL && !attacker.pbHasType?(:ICE)) || (pbWeather==PBWeather::SANDSTORM && !attacker.pbHasType?(:ROCK) && !attacker.pbHasType?(:GROUND) && !attacker.pbHasType?(:STEEL))
                score*=2
              end
            end
          end
        else
          score*=0.9
        end
        if attacker.effects[PBEffects::Toxic]>0
          score*=0.5
          if attacker.effects[PBEffects::Toxic]>4
            score*=0.5
          end
        end
        if attacker.status==PBStatuses::PARALYSIS || attacker.effects[PBEffects::Attract]>=0 || attacker.effects[PBEffects::Confusion]>0
          score*=1.1
        end
        if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::Curse]
          score*=1.3
          if opponent.effects[PBEffects::Toxic]>0
            score*=1.3
          end
        end
        score*=1.3 if checkAImoves(PBStuff::CONTRARYBAITMOVE,aimem)
        if opponent.vanished || opponent.effects[PBEffects::HyperBeam]>0
          score*=1.2
        end
        if pbWeather==PBWeather::SUNNYDAY
          score*=1.3
        elsif pbWeather==PBWeather::SANDSTORM || pbWeather==PBWeather::RAINDANCE || pbWeather==PBWeather::HAIL
          score*=0.5
        end
        if skill>=PBTrainerAI.bestSkill
          if move.id==(PBMoves::MOONLIGHT)
            if $fefieldeffect==4 || $fefieldeffect==34 || $fefieldeffect==35  # Dark Crystal/Starlight/New World
              score*=1.3
            end
          else
            if $fefieldeffect==4
              score*=0.5
            end
          end
        end
        if ((attacker.hp.to_f)/attacker.totalhp)>0.8
          score=0
        elsif ((attacker.hp.to_f)/attacker.totalhp)>0.6
          score*=0.6
        elsif ((attacker.hp.to_f)/attacker.totalhp)<0.25
          score*=2
        end
        if attacker.effects[PBEffects::Wish]>0
            score=0
        end
      when 0xD9 # Rest
        if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
          score*=3
        else
          if skill>=PBTrainerAI.bestSkill
            if checkAIdamage(aimem,attacker,opponent,skill)*1.5>attacker.hp
              score*=1.5
            end
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              if checkAIdamage(aimem,attacker,opponent,skill)*2>attacker.hp
                score*=2
              end
            end
          end
        end
        if (attacker.hp.to_f)/attacker.totalhp<0.5
          score*=1.5
        else
          score*=0.5
        end
        if (roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL))
          score*=1.2
        end
        if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::Curse]
          score*=1.3
          if opponent.effects[PBEffects::Toxic]>0
            score*=1.3
          end
        end
        if attacker.status==PBStatuses::POISON
          score*=1.3
          if opponent.effects[PBEffects::Toxic]>0
            score*=1.3
          end
        end
        if attacker.status==PBStatuses::BURN
          score*=1.3
          if attacker.spatk<attacker.attack
            score*=1.5
          end
        end
        if attacker.status==PBStatuses::PARALYSIS
          score*=1.3
        end
        score*=1.3 if checkAImoves(PBStuff::CONTRARYBAITMOVE,aimem)
        if attacker.hp*(1.0/attacker.totalhp)>=0.8
          score*=0
        end
        if !((attitemworks && attacker.item == PBItems::LUMBERRY) || (attitemworks && attacker.item == PBItems::CHESTOBERRY) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::HYDRATION) && (pbWeather==PBWeather::RAINDANCE || $fefieldeffect==21 || $fefieldeffect==22)))
          score*=0.8
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if maxdam*2 > attacker.totalhp
            score*=0.4
          else
            if maxdam*3 < attacker.totalhp
              score*=1.3
              #experimental -- cancels out drop if killing moves
              if initialscores.length>0
                score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
              end
              #end experimental
            end
          end
          if checkAImoves([PBMoves::WAKEUPSLAP,PBMoves::NIGHTMARE,PBMoves::DREAMEATER],aimem) || (!opponent.abilitynulled && opponent.ability == PBAbilities::BADDREAMS)
            score*=0.7
          end
          if attacker.pbHasMove?((PBMoves::SLEEPTALK))
            score*=1.3
          end
          if attacker.pbHasMove?((PBMoves::SNORE))
            score*=1.2
          end
          if !attacker.abilitynulled && (attacker.ability == PBAbilities::SHEDSKIN || attacker.ability == PBAbilities::EARLYBIRD)
            score*=1.1
          end
          if @doublebattle
            score*=0.8
          end
        else
          if attitemworks && (attacker.item == PBItems::LUMBERRY || attacker.item == PBItems::CHESTOBERRY)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::HARVEST)
              score*=1.2
            else
              score*=0.8
            end
          end
        end
        if attacker.status!=0
          score*=1.4
          if attacker.effects[PBEffects::Toxic]>0
            score*=1.2
          end
        end
        if !attacker.pbCanSleep?(false,true,true)
          score*=0
        end
      when 0xDA # Aqua Ring
        if !attacker.effects[PBEffects::AquaRing]
          if attacker.hp*(1.0/attacker.totalhp)>0.75
            score*=1.2
          end
          if attacker.hp*(1.0/attacker.totalhp)<0.50
            score*=0.7
            if attacker.hp*(1.0/attacker.totalhp)<0.33
              score*=0.5
            end
          end
          if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::RAINDISH) && pbWeather==PBWeather::RAINDANCE) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::ICEBODY) && pbWeather==PBWeather::HAIL) || attacker.effects[PBEffects::Ingrain] || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON)) || $fefieldeffect==2
            score*=1.2
          end
          if attacker.moves.any? {|moveloop| (PBStuff::PROTECTMOVE).include?(moveloop)}
            score*=1.2
          end
          if attacker.moves.any? {|moveloop| (PBStuff::PIVOTMOVE).include?(moveloop)}
            score*=0.8
          end
          if checkAIdamage(aimem,attacker,opponent,skill)*5 < attacker.totalhp && (aimem.length > 0)
            score*=1.2
          elsif checkAIdamage(aimem,attacker,opponent,skill) > attacker.totalhp*0.4
            score*=0.3
          end
          if (roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL) || roles.include?(PBMonRoles::TANK))
            score*=1.2
          end
          score*=0.3 if checkAImoves(PBStuff::SWITCHOUTMOVE,aimem)
          if @doublebattle
            score*=0.5
          end
          if $fefieldeffect==3 || $fefieldeffect==8 || $fefieldeffect==21 || $fefieldeffect==22
            score*=1.3
          end
          if $fefieldeffect==7
            score*=1.3
          end
          if $fefieldeffect==11
            score*=0.3
          end
        else
          score*=0
        end
      when 0xDB # Ingrain
        if !attacker.effects[PBEffects::Ingrain]
          if attacker.hp*(1.0/attacker.totalhp)>0.75
            score*=1.2
          end
          if attacker.hp*(1.0/attacker.totalhp)<0.50
            score*=0.7
            if attacker.hp*(1.0/attacker.totalhp)<0.33
              score*=0.5
            end
          end
          if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::RAINDISH) && pbWeather==PBWeather::RAINDANCE) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::ICEBODY) && pbWeather==PBWeather::HAIL) || attacker.effects[PBEffects::AquaRing] || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON)) || $fefieldeffect==2
            score*=1.2
          end
          if attacker.moves.any? {|moveloop| (PBStuff::PROTECTMOVE).include?(moveloop)}
            score*=1.2
          end
          if attacker.moves.any? {|moveloop| (PBStuff::PIVOTMOVE).include?(moveloop)}
            score*=0.8
          end
          if checkAIdamage(aimem,attacker,opponent,skill)*5 < attacker.totalhp && (aimem.length > 0)
            score*=1.2
          elsif checkAIdamage(aimem,attacker,opponent,skill) > attacker.totalhp*0.4
            score*=0.3
          end
          if (roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL) || roles.include?(PBMonRoles::TANK))
            score*=1.2
          end

          score*=0.3 if checkAImoves(PBStuff::SWITCHOUTMOVE,aimem)
          if @doublebattle
            score*=0.5
          end
          if $fefieldeffect==15 || $fefieldeffect==33
            score*=1.3
            if $fefieldeffect==33 && $fecounter>3
              score*=1.3
            end
          end
          if $fefieldeffect==8
            score*=0.1 unless (attacker.pbHasType?(:POISON) || attacker.pbHasType?(:STEEL))
          end
          if $fefieldeffect==10
            score*=0.1
          end
        else
          score*=0
        end
      when 0xDC # Leech Seed
        if opponent.effects[PBEffects::LeechSeed]<0 && ! opponent.pbHasType?(:GRASS) && opponent.effects[PBEffects::Substitute]<=0
          if (roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL) || roles.include?(PBMonRoles::TANK))
            score*=1.2
          end
          if attacker.effects[PBEffects::Substitute]>0
            score*=1.3
          end
          if opponent.hp==opponent.totalhp
            score*=1.1
          else
            score*=(opponent.hp*(1.0/opponent.totalhp))
          end
          if (oppitemworks && opponent.item == PBItems::LEFTOVERS) || (oppitemworks && opponent.item == PBItems::BIGROOT) || ((oppitemworks && opponent.item == PBItems::BLACKSLUDGE) && opponent.pbHasType?(:POISON))
            score*=1.2
          end
          if opponent.status==PBStatuses::PARALYSIS || opponent.status==PBStatuses::SLEEP
            score*=1.2
          end
          if opponent.effects[PBEffects::Confusion]>0
            score*=1.2
          end
          if opponent.effects[PBEffects::Attract]>=0
            score*=1.2
          end
          if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN
            score*=1.1
          end
          score*=0.2 if checkAImoves([PBMoves::RAPIDSPIN,PBMoves::UTURN,PBMoves::VOLTSWITCH],aimem)
          if opponent.hp*2<opponent.totalhp
            score*=0.8
            if opponent.hp*4<opponent.totalhp
              score*=0.2
            end
          end
          protectmove=false
          for j in attacker.moves
            protectmove = true if j.id==(PBMoves::PROTECT) || j.id==(PBMoves::DETECT) || j.id==(PBMoves::BANEFULBUNKER) || j.id==(PBMoves::SPIKYSHIELD)
          end
          if protectmove
            score*=1.2
          end
          ministat= (5)* statchangecounter(opponent,1,7,1)
          ministat+=100
          ministat/=100.0
          score*=ministat
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::LIQUIDOOZE) || opponent.effects[PBEffects::Substitute]>0
            score*=0
          end
        else
          score*=0
        end
      when 0xDD # Drain Punch
        minimini = score*0.01
        miniscore = (opponent.hp*minimini)/2.0
        if miniscore > (attacker.totalhp-attacker.hp)
          miniscore = (attacker.totalhp-attacker.hp)
        end
        if attacker.totalhp>0
          miniscore/=(attacker.totalhp).to_f
        end
        if (attitemworks && attacker.item == PBItems::BIGROOT)
          miniscore*=1.3
        end
        miniscore *= 0.5 #arbitrary multiplier to make it value the HP less
        miniscore+=1
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::LIQUIDOOZE)
          miniscore = (2-miniscore)
        end
        if (attacker.hp!=attacker.totalhp || ((attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0))) && opponent.effects[PBEffects::Substitute]==0
          score*=miniscore
        end
        ghostvar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:GHOST)
            ghostvar=true
          end
        end
        if move.id==(PBMoves::PARABOLICCHARGE)
          if $fefieldeffect==18
            score*=1.1
            if ghostvar
              score*=0.8
            end
          end
        end
      when 0xDE # Dream Eater
        if opponent.status==PBStatuses::SLEEP
          minimini = score*0.01
          miniscore = (opponent.hp*minimini)/2.0
          if miniscore > (attacker.totalhp-attacker.hp)
            miniscore = (attacker.totalhp-attacker.hp)
          end
          if attacker.totalhp>0
            miniscore/=(attacker.totalhp).to_f
          end
          if (attitemworks && attacker.item == PBItems::BIGROOT)
            miniscore*=1.3
          end
          miniscore+=1
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::LIQUIDOOZE)
            miniscore = (2-miniscore)
          end
          if (attacker.hp!=attacker.totalhp || ((attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0))) && opponent.effects[PBEffects::Substitute]==0
            score*=miniscore
          end
        else
          score*=0
        end
      when 0xDF # Heal Pulse
        if !@doublebattle || attacker.opposes?(opponent.index)
          score*=0
        else
          if !attacker.opposes?(opponent.index)
            if opponent.hp*(1.0/opponent.totalhp)<0.7 && opponent.hp*(1.0/opponent.totalhp)>0.3
              score*=3
            elsif opponent.hp*(1.0/opponent.totalhp)<0.3
              score*=1.7
            end
            if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::Curse]
              score*=0.8
              if opponent.effects[PBEffects::Toxic]>0
                score*=0.7
              end
            end
            if opponent.hp*(1.0/opponent.totalhp)>0.8
              if ((attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && ((attacker.pbSpeed<pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0))
                score*=0.5
              else
                score*=0
              end
            end
          else
            score*=0
          end
        end
      when 0xE0 # Explosion
        score*=0.7
        if attacker.hp==attacker.totalhp
          score*=0.2
        else
          miniscore = attacker.hp*(1.0/attacker.totalhp)
          miniscore = 1-miniscore
          score*=miniscore
          if attacker.hp*4<attacker.totalhp
            score*=1.3
            if (attitemworks && attacker.item == PBItems::CUSTAPBERRY)
              score*=1.4
            end
          end
        end
        if roles.include?(PBMonRoles::LEAD)
          score*=1.2
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::DISGUISE) || opponent.effects[PBEffects::Substitute]>0
          score*=0.3
        end
        score*=0.3 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
        firevar=false
        poisonvar=false
        ghostvar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:FIRE)
            firevar=true
          end
          if mon.hasType?(:POISON)
            poisonvar=true
          end
          if mon.hasType?(:GHOST)
            ghostvar=true
          end
        end
        if $fefieldeffect==16
          if pbWeather!=PBWeather::RAINDANCE && @field.effects[PBEffects::WaterSport]==0
            if firevar
              score*=2
            else
              score*=0.5
            end
          end
        elsif $fefieldeffect==11
          if !poisonvar
            score*=1.5
          else
            score*=0.5
          end
        elsif $fefieldeffect==24
          score*=1.5
        elsif $fefieldeffect==17
          score*=1.1
          if ghostvar
            score*=1.3
          end
        end
        if $fefieldeffect==3 || $fefieldeffect==8 || pbCheckGlobalAbility(:DAMP)
          score*=0
        end
      when 0xE1 # Final Gambit
        score*=0.7
        if attacker.hp > opponent.hp
          score*=1.1
        else
          score*=0.5
        end
        if (attacker.pbSpeed>pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=1.1
        else
          score*=0.5
        end
        if (oppitemworks && opponent.item == PBItems::FOCUSSASH) || (!opponent.abilitynulled && opponent.ability == PBAbilities::STURDY)
          score*=0.2
        end
      when 0xE2 # Memento
        if initialscores.length>0
          score = 15 if hasbadmoves(initialscores,scoreindex,10)
        end
        if attacker.hp==attacker.totalhp
          score*=0.2
        else
          miniscore = attacker.hp*(1.0/attacker.totalhp)
          miniscore = 1-miniscore
          score*=miniscore
          if attacker.hp*4<attacker.totalhp
            score*=1.3
          end
        end
        if opponent.attack > opponent.spatk
          if opponent.stages[PBStats::ATTACK]<-1
            score*=0.1
          end
        else
          if opponent.stages[PBStats::SPATK]<-1
            score*=0.1
          end
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::CLEARBODY) || (!opponent.abilitynulled && opponent.ability == PBAbilities::WHITESMOKE)
          score*=0
        end
      when 0xE3 # Healing Wish
        count=0
        for mon in pbParty(opponent.index)
          next if mon.nil?
          count+=1 if mon.hp!=mon.totalhp
        end
        count-=1 if attacker.hp!=attacker.totalhp
        if count==0
          score*=0
        else
          maxscore = 0
          for mon in pbParty(opponent.index)
            next if mon.nil?
            if mon.hp!=mon.totalhp
              miniscore = 1 - mon.hp*(1.0/mon.totalhp)
              miniscore*=2 if mon.status!=0
              maxscore=miniscore if miniscore>maxscore
            end
          end
          score*=maxscore
        end
        if attacker.hp==attacker.totalhp
          score*=0.2
        else
          miniscore = attacker.hp*(1.0/attacker.totalhp)
          miniscore = 1-miniscore
          score*=miniscore
          if attacker.hp*4<attacker.totalhp
            score*=1.3
            if (attitemworks && attacker.item == PBItems::CUSTAPBERRY)
              score*=1.4
            end
          end
        end
        if (attacker.pbSpeed>pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=1.1
        else
          score*=0.5
        end
        if $fefieldeffect==31 || $fefieldeffect==34
          score*=1.4
        end
      when 0xE4 # Lunar Dance
        count=0
        for mon in pbParty(opponent.index)
          next if mon.nil?
          count+=1 if mon.hp!=mon.totalhp
        end
        count-=1 if attacker.hp!=attacker.totalhp
        if count==0
          score*=0
        else
          maxscore = 0
          score*=1.2
          for mon in pbParty(opponent.index)
            next if mon.nil?
            if mon.hp!=mon.totalhp
              miniscore = 1 - mon.hp*(1.0/mon.totalhp)
              miniscore*=2 if mon.status!=0
              maxscore=miniscore if miniscore>maxscore
            end
          end
          score*=maxscore
        end
        if attacker.hp==attacker.totalhp
          score*=0.2
        else
          miniscore = attacker.hp*(1.0/attacker.totalhp)
          miniscore = 1-miniscore
          score*=miniscore
          if attacker.hp*4<attacker.totalhp
            score*=1.3
            if (attitemworks && attacker.item == PBItems::CUSTAPBERRY)
              score*=1.4
            end
          end
        end
        if (attacker.pbSpeed>pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=1.1
        else
          score*=0.5
        end
        if $fefieldeffect==31 || $fefieldeffect==34
          score*=1.4
        elsif $fefieldeffect==35
          score*=2
        end
      when 0xE5 # Perish Song
        livecount1=0
        for i in pbParty(opponent.index)
          next if i.nil?
          livecount1+=1 if i.hp!=0
        end
        livecount2=0
        for i in pbParty(attacker.index)
          next if i.nil?
          livecount2+=1 if i.hp!=0
        end
        if livecount1==1 || (livecount1==2 && @doublebattle)
          score*=4
        else
          if attacker.pbHasMove?((PBMoves::UTURN)) || attacker.pbHasMove?((PBMoves::VOLTSWITCH))
            score*=1.5
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || opponent.effects[PBEffects::MeanLook]>0
            score*=3
          end
          if attacker.pbHasMove?((PBMoves::PROTECT))
            score*=1.2
          end
          count = -1
          sweepvar = false
          for i in pbParty(attacker.index)
            count+=1
            next if i.nil?
            temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
            if temprole.include?(PBMonRoles::SWEEPER)
              sweepvar = true
            end
          end
          score*=1.2 if sweepvar
          for j in attacker.moves
            if j.isHealingMove?
              score*=1.2
              break
            end
          end
          miniscore=(-5)*statchangecounter(attacker,1,7)
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
          miniscore= 5*statchangecounter(opponent,1,7)
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
          score*=0.5 if checkAImoves(PBStuff::PIVOTMOVE,aimem)
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SHADOWTAG) || attacker.effects[PBEffects::MeanLook]>0
            score*=0.1
          end
          count = -1
          pivotvar = false
          for i in pbParty(attacker.index)
            count+=1
            next if i.nil?
            temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
            if temprole.include?(PBMonRoles::PIVOT)
              pivotvar = true
            end
          end
          score*=1.5 if pivotvar
          if livecount2==1 || (livecount2==2 && @doublebattle)
            score*=0
          end
        end
        score*=0 if opponent.effects[PBEffects::PerishSong]>0
      when 0xE6 # Grudge
        movenum = 0
        damcount =0
        if aimem.length > 0
          for j in aimem
            movenum+=1
            if j.basedamage>0
              damcount+=1
            end
          end
        end
        if movenum==4 && damcount==1
          score*=3
        end
        if attacker.hp==attacker.totalhp
          score*=0.2
        else
          miniscore = attacker.hp*(1.0/attacker.totalhp)
          miniscore = 1-miniscore
          score*=miniscore
          if attacker.hp*4<attacker.totalhp
            score*=1.3
            if (attitemworks && attacker.item == PBItems::CUSTAPBERRY)
              score*=1.3
            end
          end
        end
        if (attacker.pbSpeed>pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=1.3
        else
          score*=0.5
        end
      when 0xE7 # Destiny Bond
        movenum = 0
        damcount =0
        if aimem.length > 0
          for j in aimem
            movenum+=1
            if j.basedamage>0
              damcount+=1
            end
          end
        end
        if movenum==4 && damcount==4
          score*=3
        end
        if initialscores.length>0
          score*=0.1 if hasgreatmoves(initialscores,scoreindex,skill)
        end
        if attacker.hp==attacker.totalhp
          score*=0.2
        else
          miniscore = attacker.hp*(1.0/attacker.totalhp)
          miniscore = 1-miniscore
          score*=miniscore
          if attacker.hp*4<attacker.totalhp
            score*=1.3
            if (attitemworks && attacker.item == PBItems::CUSTAPBERRY)
              score*=1.5
            end
          end
        end
        if (attacker.pbSpeed>pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=1.5
        else
          score*=0.5
        end
        if attacker.effects[PBEffects::DestinyRate]>1
          score*=0
        end
      when 0xE8 # Endure
        if attacker.hp>1
          if attacker.hp==attacker.totalhp && ((attitemworks && attacker.item == PBItems::FOCUSSASH) || (!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY))
            score*=0
          end
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=2
          end
          if (attacker.pbSpeed>pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.3
          else
            score*=0.5
          end
          if (pbWeather==PBWeather::HAIL && !attacker.pbHasType?(:ICE)) || (pbWeather==PBWeather::SANDSTORM && !(attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
            score*=0
          end
          if $fefieldeffect==7 || $fefieldeffect==26
            score*=0
          end
          if attacker.status==PBStatuses::POISON || attacker.status==PBStatuses::BURN || attacker.effects[PBEffects::LeechSeed]>=0 || attacker.effects[PBEffects::Curse]
            score*=0
          end
          if attacker.pbHasMove?((PBMoves::PAINSPLIT)) || attacker.pbHasMove?((PBMoves::FLAIL)) || attacker.pbHasMove?((PBMoves::REVERSAL))
            score*=2
          end
          if attacker.pbHasMove?((PBMoves::ENDEAVOR))
            score*=3
          end
          if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::Curse]
            score*=1.5
          end
          if opponent.effects[PBEffects::TwoTurnAttack]!=0
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=15
            end
          end
        else
          score*=0
        end
      when 0xE9 # False Swipe
        if score>=100
          score*=0.1
        end
      when 0xEA # Teleport
        score*=0
      when 0xEB # Roar
        if opponent.pbOwnSide.effects[PBEffects::StealthRock]
          score*=1.3
        else
          score*=0.8
        end
        if opponent.pbOwnSide.effects[PBEffects::Spikes]>0
          score*=(1.2**opponent.pbOwnSide.effects[PBEffects::Spikes])
        else
          score*=0.8
        end
        if opponent.pbOwnSide.effects[PBEffects::ToxicSpikes]>0
          score*=1.1
        end
        ministat = 10*statchangecounter(opponent,1,7)
        ministat+=100
        ministat/=100.0
        score*=ministat
        if opponent.effects[PBEffects::PerishSong]>0 || opponent.effects[PBEffects::Yawn]>0
          score*=0
        end
        if opponent.status==PBStatuses::SLEEP
          score*=1.3
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::SLOWSTART)
          score*=1.3
        end
        if opponent.item ==0 && (!opponent.abilitynulled && opponent.ability == PBAbilities::UNBURDEN)
          score*=1.5
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::INTIMIDATE)
          score*=0.7
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::REGENERATOR) || (!opponent.abilitynulled && opponent.ability == PBAbilities::NATURALCURE)
          score*=0.5
        end
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=0.8
        end
        if attacker.effects[PBEffects::Substitute]>0
          score*=1.4
        end
        firevar=false
        poisonvar=false
        fairytvar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:FIRE)
            firevar=true
          end
          if mon.hasType?(:POISON)
            poisonvar=true
          end
          if mon.hasType?(:FAIRY)
            fairyvar=true
          end
        end
        if $fefieldeffect==3
          score*=1.3
          if !fairyvar
            score*=1.3
          else
            score*=0.8
          end
        elsif $fefielfeffect==7
          if !firevar
            score*=1.8
          else
            score*=0.5
          end
        elsif $fefieldeffect==11
          if !poisonvar
            score*=3
          else
            score*=0.8
          end
        end
        if opponent.effects[PBEffects::Ingrain] || (!opponent.abilitynulled && opponent.ability == PBAbilities::SUCTIONCUPS) || opponent.pbNonActivePokemonCount==0
          score*=0
        end
      when 0xEC # Dragon Tail
        if opponent.effects[PBEffects::Substitute]<=0
          miniscore=1
          if opponent.pbOwnSide.effects[PBEffects::StealthRock]
            miniscore*=1.3
          else
            miniscore*=0.8
          end
          if opponent.pbOwnSide.effects[PBEffects::Spikes]>0
            miniscore*=(1.2**opponent.pbOwnSide.effects[PBEffects::Spikes])
          else
            miniscore*=0.8
          end
          if opponent.pbOwnSide.effects[PBEffects::ToxicSpikes]>0
            miniscore*=1.1
          end
          ministat = 10*statchangecounter(opponent,1,7)
          ministat+=100
          ministat/=100.0
          miniscore*=ministat
          if opponent.status==PBStatuses::SLEEP
            miniscore*=1.3
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SLOWSTART)
            miniscore*=1.3
          end
          if opponent.item ==0 && (!opponent.abilitynulled && opponent.ability == PBAbilities::UNBURDEN)
            miniscore*=1.5
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::INTIMIDATE)
            miniscore*=0.7
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::REGENERATOR) || (!opponent.abilitynulled && opponent.ability == PBAbilities::NATURALCURE)
            miniscore*=0.5
          end
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            miniscore*=0.8
          end
          if opponent.effects[PBEffects::PerishSong]>0 || opponent.effects[PBEffects::Yawn]>0
            miniscore=1
          end
          if attacker.effects[PBEffects::Substitute]>0
            miniscore=1
          end
          if opponent.effects[PBEffects::Ingrain] || (!opponent.abilitynulled && opponent.ability == PBAbilities::SUCTIONCUPS) || opponent.pbNonActivePokemonCount==0
            miniscore=1
          end
          score*=miniscore
        end
      when 0xED # Baton Pass
        if pbCanChooseNonActive?(attacker.index)
          ministat = 10*statchangecounter(attacker,1,7)
          ministat+=100
          ministat/=100.0
          score*=ministat
          if attacker.effects[PBEffects::Substitute]>0
            score*=1.3
          end
          if attacker.effects[PBEffects::Confusion]>0
            score*=0.5
          end
          if attacker.effects[PBEffects::LeechSeed]>=0
            score*=0.5
          end
          if attacker.effects[PBEffects::Curse]
            score*=0.5
          end
          if attacker.effects[PBEffects::Yawn]>0
            score*=0.5
          end
          if attacker.turncount<1
            score*=0.5
          end
          damvar = false
          for i in attacker.moves
            if i.basedamage>0
              damvar=true
            end
          end
          if !damvar
            score*=1.3
          end
          if attacker.effects[PBEffects::Ingrain] || attacker.effects[PBEffects::AquaRing]
            score*=1.2
          end
          if attacker.effects[PBEffects::PerishSong]>0
            score*=0
          else
            if initialscores.length>0
              if damvar
                if initialscores.max>30
                  score*=0.7
                  if initialscores.max>50
                    score*=0.3
                  end
                end
              end
            end
          end
        else
          score*=0
        end
      when 0xEE # U-Turn
        livecount=0
        for i in pbParty(attacker.index)
          next if i.nil?
          livecount+=1 if i.hp!=0
        end
        if livecount>1
          if livecount==2
            if $game_switches[1000]
              score*=0
            end
          end
          if initialscores.length>0
            greatmoves=false
            badmoves=true
            iffymoves=true
            for i in 0...initialscores.length
              next if i==scoreindex
              if initialscores[i]>=110
                greatmoves=true
              end
              if initialscores[i]>=25
                badmoves=false
              end
              if initialscores[i]>=50
                iffymoves=false
              end
            end
            score*=0.5 if greatmoves
            if badmoves == true
              score+=40
            elsif iffymoves == true
              score+=20
            end
          end
          if attacker.pbOwnSide.effects[PBEffects::StealthRock]
            score*=0.7
          end
          if attacker.pbOwnSide.effects[PBEffects::StickyWeb]
            score*=0.6
          end
          if attacker.pbOwnSide.effects[PBEffects::Spikes]>0
            score*=0.9**attacker.pbOwnSide.effects[PBEffects::Spikes]
          end
          if attacker.pbOwnSide.effects[PBEffects::ToxicSpikes]>0
            score*=0.9**attacker.pbOwnSide.effects[PBEffects::ToxicSpikes]
          end
          count = -1
          sweepvar = false
          for i in pbParty(attacker.index)
            count+=1
            next if i.nil?
            temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
            if temprole.include?(PBMonRoles::SWEEPER)
              sweepvar = true
            end
          end
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.2
          else
            if sweepvar
              score*=1.2
            end
          end
          if roles.include?(PBMonRoles::LEAD)
            score*=1.2
          end
          if roles.include?(PBMonRoles::PIVOT)
            score*=1.1
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::REGENERATOR) && ((attacker.hp.to_f)/attacker.totalhp)<0.75
            score*=1.2
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::REGENERATOR) && ((attacker.hp.to_f)/attacker.totalhp)<0.5
              score*=1.2
            end
          end
          loweredstats=0
          loweredstats+=attacker.stages[PBStats::ATTACK] if attacker.stages[PBStats::ATTACK]<0
          loweredstats+=attacker.stages[PBStats::DEFENSE] if attacker.stages[PBStats::DEFENSE]<0
          loweredstats+=attacker.stages[PBStats::SPEED] if attacker.stages[PBStats::SPEED]<0
          loweredstats+=attacker.stages[PBStats::SPATK] if attacker.stages[PBStats::SPATK]<0
          loweredstats+=attacker.stages[PBStats::SPDEF] if attacker.stages[PBStats::SPDEF]<0
          loweredstats+=attacker.stages[PBStats::EVASION] if attacker.stages[PBStats::EVASION]<0
          miniscore= (-15)*loweredstats
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
          raisedstats=0
          raisedstats+=attacker.stages[PBStats::ATTACK] if attacker.stages[PBStats::ATTACK]>0
          raisedstats+=attacker.stages[PBStats::DEFENSE] if attacker.stages[PBStats::DEFENSE]>0
          raisedstats+=attacker.stages[PBStats::SPEED] if attacker.stages[PBStats::SPEED]>0
          raisedstats+=attacker.stages[PBStats::SPATK] if attacker.stages[PBStats::SPATK]>0
          raisedstats+=attacker.stages[PBStats::SPDEF] if attacker.stages[PBStats::SPDEF]>0
          raisedstats+=attacker.stages[PBStats::EVASION] if attacker.stages[PBStats::EVASION]>0
          miniscore= (-25)*raisedstats
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
          if attacker.effects[PBEffects::Toxic]>0 || attacker.effects[PBEffects::Attract]>-1 || attacker.effects[PBEffects::Confusion]>0
            score*=1.3
          end
          if attacker.effects[PBEffects::LeechSeed]>-1
            score*=1.5
          end
        end
      when 0xEF # Mean Look
        if !(opponent.effects[PBEffects::MeanLook]>=0 || opponent.effects[PBEffects::Ingrain] || opponent.pbHasType?(:GHOST)) && opponent.effects[PBEffects::Substitute]<=0
          score*=0.1 if checkAImoves(PBStuff::PIVOTMOVE,aimem)
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::RUNAWAY)
            score*=0.1
          end
          if attacker.pbHasMove?((PBMoves::PERISHSONG))
            score*=1.5
          end
          if opponent.effects[PBEffects::PerishSong]>0
            score*=4
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::ARENATRAP) || (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG)
            score*=0
          end
          if opponent.effects[PBEffects::Attract]>=0
            score*=1.3
          end
          if opponent.effects[PBEffects::LeechSeed]>=0
            score*=1.3
          end
          if opponent.effects[PBEffects::Curse]
            score*=1.5
          end
          miniscore*=0.7 if attacker.moves.any? {|moveloop| (PBStuff::SWITCHOUTMOVE).include?(moveloop)}
          ministat = (-5)*statchangecounter(opponent,1,7)
          ministat+=100
          ministat/=100.0
          score*=ministat
          if opponent.effects[PBEffects::Confusion]>0
            score*=1.1
          end
        else
          score*=0
        end
      when 0xF0 # Knock Off
        if !hasgreatmoves(initialscores,scoreindex,skill) && opponent.effects[PBEffects::Substitute]<=0
          if (!(!opponent.abilitynulled && opponent.ability == PBAbilities::STICKYHOLD) || opponent.moldbroken) && opponent.item!=0 && !pbIsUnlosableItem(opponent,opponent.item)
            score*=1.1
            if oppitemworks
              if opponent.item == PBItems::LEFTOVERS || (opponent.item == PBItems::BLACKSLUDGE) && opponent.pbHasType?(:POISON)
                score*=1.2
              elsif opponent.item == PBItems::LIFEORB || opponent.item == PBItems::CHOICESCARF || opponent.item == PBItems::CHOICEBAND || opponent.item == PBItems::CHOICESPECS || opponent.item == PBItems::ASSAULTVEST
                score*=1.1
              end
            end
          end
        end
      when 0xF1 # Covet
        if (!(!opponent.abilitynulled && opponent.ability == PBAbilities::STICKYHOLD) || opponent.moldbroken) && opponent.item!=0 && !pbIsUnlosableItem(opponent,opponent.item) && attacker.item ==0 && opponent.effects[PBEffects::Substitute]<=0
          miniscore = 1.2
          case opponent.item
            when (PBItems::LEFTOVERS), (PBItems::LIFEORB), (PBItems::LUMBERRY), (PBItems::SITRUSBERRY)
              miniscore*=1.5
            when (PBItems::ASSAULTVEST), (PBItems::ROCKYHELMET), (PBItems::MAGICALSEED), (PBItems::SYNTHETICSEED), (PBItems::TELLURICSEED), (PBItems::ELEMENTALSEED)
              miniscore*=1.3
            when (PBItems::FOCUSSASH), (PBItems::MUSCLEBAND), (PBItems::WISEGLASSES), (PBItems::EXPERTBELT), (PBItems::WIDELENS)
              miniscore*=1.2
            when (PBItems::CHOICESCARF)
              if attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
                miniscore*=1.1
              end
            when (PBItems::CHOICEBAND)
              if attacker.attack>attacker.spatk
                miniscore*=1.1
              end
            when (PBItems::CHOICESPECS)
              if attacker.spatk>attacker.attack
                miniscore*=1.1
              end
            when (PBItems::BLACKSLUDGE)
              if attacker.pbHasType?(:POISON)
                miniscore*=1.5
              else
                miniscore*=0.5
              end
            when (PBItems::TOXICORB), (PBItems::FLAMEORB), (PBItems::LAGGINGTAIL), (PBItems::IRONBALL), (PBItems::STICKYBARB)
              miniscore*=0.5
          end
          score*=miniscore
        end
      when 0xF2 # Trick
        statvar = false
        for m in opponent.moves
          if m.basedamage==0
            statvar=true
          end
        end
        if (!(!opponent.abilitynulled && opponent.ability == PBAbilities::STICKYHOLD) || opponent.moldbroken) && opponent.effects[PBEffects::Substitute]<=0
          miniscore = 1
          minimini = 1
          if opponent.item!=0 && !pbIsUnlosableItem(opponent,opponent.item)
            miniscore*=1.2
            case opponent.item
              when (PBItems::LEFTOVERS), (PBItems::LIFEORB), (PBItems::LUMBERRY), (PBItems::SITRUSBERRY)
                miniscore*=1.5
              when (PBItems::ASSAULTVEST), (PBItems::ROCKYHELMET), (PBItems::MAGICALSEED), (PBItems::SYNTHETICSEED), (PBItems::TELLURICSEED), (PBItems::ELEMENTALSEED)
                miniscore*=1.3
              when (PBItems::FOCUSSASH), (PBItems::MUSCLEBAND), (PBItems::WISEGLASSES), (PBItems::EXPERTBELT), (PBItems::WIDELENS)
                miniscore*=1.2
              when (PBItems::CHOICESCARF)
                if ((attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0))
                  miniscore*=1.1
                end
              when (PBItems::CHOICEBAND)
                if attacker.attack>attacker.spatk
                  miniscore*=1.1
                end
              when (PBItems::CHOICESPECS)
                if attacker.spatk>attacker.attack
                  miniscore*=1.1
                end
              when (PBItems::BLACKSLUDGE)
                if attacker.pbHasType?(:POISON)
                  miniscore*=1.5
                else
                  miniscore*=0.5
                end
              when (PBItems::TOXICORB), (PBItems::FLAMEORB), (PBItems::LAGGINGTAIL), (PBItems::IRONBALL), (PBItems::STICKYBARB)
                miniscore*=0.5
            end
          end
          if attacker.item!=0 && !pbIsUnlosableItem(attacker,attacker.item)
            minimini*=0.8
            case attacker.item
              when (PBItems::LEFTOVERS), (PBItems::LIFEORB), (PBItems::LUMBERRY), (PBItems::SITRUSBERRY)
                minimini*=0.5
              when (PBItems::ASSAULTVEST), (PBItems::ROCKYHELMET), (PBItems::MAGICALSEED), (PBItems::SYNTHETICSEED), (PBItems::TELLURICSEED), (PBItems::ELEMENTALSEED)
                minimini*=0.7
              when (PBItems::FOCUSSASH), (PBItems::MUSCLEBAND), (PBItems::WISEGLASSES), (PBItems::EXPERTBELT), (PBItems::WIDELENS)
                minimini*=0.8
              when (PBItems::CHOICESCARF)
                if ((attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0))
                  minimini*=1.5
                else
                  minimini*=0.9
                end
                if statvar
                  minimini*=1.3
                end
              when (PBItems::CHOICEBAND)
                if opponent.attack<opponent.spatk
                  minimini*=1.7
                end
                if attacker.attack>attacker.spatk
                  minimini*=0.8
                end
                if statvar
                  minimini*=1.3
                end
              when (PBItems::CHOICESPECS)
                if opponent.attack>opponent.spatk
                  minimini*=1.7
                end
                if attacker.attack<attacker.spatk
                  minimini*=0.8
                end
                if statvar
                  minimini*=1.3
                end
              when (PBItems::BLACKSLUDGE)
                if !attacker.pbHasType?(:POISON)
                  minimini*=1.5
                else
                  minimini*=0.5
                end
                if !opponent.pbHasType?(:POISON)
                  minimini*=1.3
                end
              when (PBItems::TOXICORB), (PBItems::FLAMEORB), (PBItems::LAGGINGTAIL), (PBItems::IRONBALL), (PBItems::STICKYBARB)
                minimini*=1.5
            end
          end
          score*=(miniscore*minimini)
        else
          score*=0
        end
        if attacker.item ==opponent.item
          score*=0
        end
      when 0xF3 # Bestow
        if (!(!opponent.abilitynulled && opponent.ability == PBAbilities::STICKYHOLD) || opponent.moldbroken) && attacker.item!=0 && opponent.item ==0 && !pbIsUnlosableItem(attacker,attacker.item) && opponent.effects[PBEffects::Substitute]<=0
          case attacker.item
            when (PBItems::CHOICESPECS)
              if opponent.attack>opponent.spatk
                score+=35
              end
            when (PBItems::CHOICESCARF)
              if (opponent.pbSpeed>attacker.pbSpeed) ^ (@trickroom!=0)
                score+=25
              end
            when (PBItems::CHOICEBAND)
              if opponent.attack<opponent.spatk
                score+=35
              end
            when (PBItems::BLACKSLUDGE)
              if !attacker.pbHasType?(:POISON)
                score+=15
              end
              if !opponent.pbHasType?(:POISON)
                score+=15
              end
            when (PBItems::TOXICORB), (PBItems::FLAMEORB)
              score+=35
            when (PBItems::LAGGINGTAIL), (PBItems::IRONBALL)
              score+=20
            when (PBItems::STICKYBARB)
              score+=25
          end
        else
          score*=0
        end
      when 0xF4 # Bug Bite
        if opponent.effects[PBEffects::Substitute]==0 && pbIsBerry?(opponent.item)
          case opponent.item
            when (PBItems::LUMBERRY)
              score*=2 if attacker.stats!=0
            when (PBItems::SITRUSBERRY)
              score*=1.6 if attacker.hp*(1.0/attacker.totalhp)<0.66
            when (PBItems::LIECHIBERRY)
              score*=1.5 if attacker.attack>attacker.spatk
            when (PBItems::PETAYABERRY)
              score*=1.5 if attacker.spatk>attacker.attack
            when (PBItems::CUSTAPBERRY), (PBItems::SALACBERRY)
              score*=1.1
              score*=1.4 if ((attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0))
          end
        end
      when 0xF5 # Incinerate
        if (pbIsBerry?(opponent.item) || pbIsTypeGem?(opponent.item)) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::STICKYHOLD) && opponent.effects[PBEffects::Substitute]<=0
          if pbIsBerry?(opponent.item) && opponent.item!=(PBItems::OCCABERRY)
            score*=1.2
          end
          if opponent.item ==(PBItems::LUMBERRY) || opponent.item ==(PBItems::SITRUSBERRY) || opponent.item ==(PBItems::PETAYABERRY) || opponent.item ==(PBItems::LIECHIBERRY) || opponent.item ==(PBItems::SALACBERRY) || opponent.item ==(PBItems::CUSTAPBERRY)
            score*=1.3
          end
          if pbIsTypeGem?(opponent.item)
            score*=1.4
          end
          firevar=false
          poisonvar=false
          bugvar=false
          grassvar=false
          icevar=false
          for mon in pbParty(attacker.index)
            next if mon.nil?
            if mon.hasType?(:FIRE)
              firevar=true
            end
            if mon.hasType?(:POISON)
              poisonvar=true
            end
            if mon.hasType?(:BUG)
              bugvar=true
            end
            if mon.hasType?(:GRASS)
              grassvar=true
            end
            if mon.hasType?(:ICE)
              icevar=true
            end
          end
          if $fefieldeffect==2 || $fefieldeffect==15 || ($fefieldeffect==33 && $fecounter>1)
            if firevar && !(bugvar || grassvar)
              score*=2
            end
          elsif $fefieldeffect==16
            if firevar
              score*=2
            end
          elsif $fefieldeffect==13 || $fefieldeffect==28
            if !icevar
              score*=1.5
            end
          end
        end
      when 0xF6 # Recycle
        if attacker.pokemon.itemRecycle!=0
          score*=2
          case attacker.pokemon.itemRecycle
            when (PBItems::LUMBERRY)
              score*=2 if attacker.stats!=0
            when (PBItems::SITRUSBERRY)
              score*=1.6 if attacker.hp*(1.0/attacker.totalhp)<0.66
              if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
                score*=1.5
              end
          end
          if pbIsBerry?(attacker.pokemon.itemRecycle)
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNNERVE)
              score*=0
            end
            score*=0 if checkAImoves([PBMoves::INCINERATE,PBMoves::PLUCK,PBMoves::BUGBITE],aimem)
          end
          score*=0 if (!opponent.abilitynulled && opponent.ability == PBAbilities::MAGICIAN) || checkAImoves([PBMoves::KNOCKOFF,PBMoves::THIEF,PBMoves::COVET],aimem)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::UNBURDEN) || (!attacker.abilitynulled && attacker.ability == PBAbilities::HARVEST) || attacker.pbHasMove?((PBMoves::ACROBATICS))
            score*=0
          end
        else
          score*=0
        end
      when 0xF7 # Fling
        if attacker.item ==0 || pbIsUnlosableItem(attacker,attacker.item) || (!attacker.abilitynulled && attacker.ability == PBAbilities::KLUTZ) || (pbIsBerry?(attacker.item) && (!opponent.abilitynulled && opponent.ability == PBAbilities::UNNERVE)) || attacker.effects[PBEffects::Embargo]>0 || @field.effects[PBEffects::MagicRoom]>0
          score*=0
        else
          case attacker.item
            when (PBItems::POISONBARB)
              if opponent.pbCanPoison?(false) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::POISONHEAL)
                score*=1.2
              end
            when (PBItems::TOXICORB)
              if opponent.pbCanPoison?(false) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::POISONHEAL)
                score*=1.2
                if attacker.pbCanPoison?(false) && !(!attacker.abilitynulled && attacker.ability == PBAbilities::POISONHEAL)
                  score*=2
                end
              end
            when (PBItems::FLAMEORB)
              if opponent.pbCanBurn?(false) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::GUTS)
                score*=1.3
                if attacker.pbCanBurn?(false) && !(!attacker.abilitynulled && attacker.ability == PBAbilities::GUTS)
                  score*=2
                end
              end
            when (PBItems::LIGHTBALL)
              if opponent.pbCanParalyze?(false) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::QUICKFEET)
                score*=1.3
              end
            when (PBItems::KINGSROCK), (PBItems::RAZORCLAW)
              if !(!opponent.abilitynulled && opponent.ability == PBAbilities::INNERFOCUS) && ((attacker.pbSpeed>opponent.pbSpeed) ^ (@trickroom!=0))
                score*=1.3
              end
            when (PBItems::POWERHERB)
              score*=0
            when (PBItems::MENTALHERB)
              score*=0
            when (PBItems::LAXINCENSE), (PBItems::CHOICESCARF), (PBItems::CHOICEBAND), (PBItems::CHOICESPECS), (PBItems::SYNTHETICSEED), (PBItems::TELLURICSEED), (PBItems::ELEMENTALSEED), (PBItems::MAGICALSEED), (PBItems::EXPERTBELT), (PBItems::FOCUSSASH), (PBItems::LEFTOVERS), (PBItems::MUSCLEBAND), (PBItems::WISEGLASSES), (PBItems::LIFEORB), (PBItems::EVIOLITE), (PBItems::ASSAULTVEST), (PBItems::BLACKSLUDGE)
              score*=0
            when (PBItems::STICKYBARB)
              score*=1.2
            when (PBItems::LAGGINGTAIL)
              score*=3
            when (PBItems::IRONBALL)
              score*=1.5
          end
          if pbIsBerry?(attacker.item)
            if attacker.item ==(PBItems::FIGYBERRY) || attacker.item ==(PBItems::WIKIBERRY) || attacker.item ==(PBItems::MAGOBERRY) || attacker.item ==(PBItems::AGUAVBERRY) || attacker.item ==(PBItems::IAPAPABERRY)
              if opponent.pbCanConfuse?(false)
                score*=1.3
              end
            else
              score*=0
            end
          end
        end
      when 0xF8 # Embargo
        startscore = score
        if opponent.effects[PBEffects::Embargo]>0  && opponent.effects[PBEffects::Substitute]>0
          score*=0
        else
          if opponent.item!=0
            score*=1.1
            if pbIsBerry?(opponent.item)
              score*=1.1
            end
            case opponent.item
              when (PBItems::LAXINCENSE), (PBItems::SYNTHETICSEED), (PBItems::TELLURICSEED), (PBItems::ELEMENTALSEED), (PBItems::MAGICALSEED), (PBItems::EXPERTBELT), (PBItems::MUSCLEBAND), (PBItems::WISEGLASSES), (PBItems::LIFEORB), (PBItems::EVIOLITE), (PBItems::ASSAULTVEST)
                score*=1.2
              when (PBItems::LEFTOVERS), (PBItems::BLACKSLUDGE)
                score*=1.3
            end
            if opponent.hp*2<opponent.totalhp
              score*=1.4
            end
          end
          if score==startscore
            score*=0
          end
        end
      when 0xF9 # Magic Room
        if @field.effects[PBEffects::MagicRoom]>0
          score*=0
        else
          if (attitemworks && attacker.item == PBItems::AMPLIFIELDROCK) || $fefieldeffect==35 || $fefieldeffect==37
            score*=1.3
          end
          if opponent.item!=0
            score*=1.1
            if pbIsBerry?(opponent.item)
              score*=1.1
            end
            case opponent.item
              when (PBItems::LAXINCENSE), (PBItems::SYNTHETICSEED), (PBItems::TELLURICSEED), (PBItems::ELEMENTALSEED), (PBItems::MAGICALSEED), (PBItems::EXPERTBELT), (PBItems::MUSCLEBAND), (PBItems::WISEGLASSES), (PBItems::LIFEORB), (PBItems::EVIOLITE), (PBItems::ASSAULTVEST)
                score*=1.2
              when (PBItems::LEFTOVERS), (PBItems::BLACKSLUDGE)
                score*=1.3
            end
          end
          if attacker.item!=0
            score*=0.8
            if pbIsBerry?(opponent.item)
              score*=0.8
            end
            case opponent.item
              when (PBItems::LAXINCENSE), (PBItems::SYNTHETICSEED), (PBItems::TELLURICSEED), (PBItems::ELEMENTALSEED), (PBItems::MAGICALSEED), (PBItems::EXPERTBELT), (PBItems::MUSCLEBAND), (PBItems::WISEGLASSES), (PBItems::LIFEORB), (PBItems::EVIOLITE), (PBItems::ASSAULTVEST)
                score*=0.6
              when (PBItems::LEFTOVERS), (PBItems::BLACKSLUDGE)
                score*=0.4
            end
          end
        end
      when 0xFA # Take Down
        if !(!attacker.abilitynulled && attacker.ability == PBAbilities::ROCKHEAD)
          score*=0.9
          if attacker.hp==attacker.totalhp && ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) || (attitemworks && attacker.item == PBItems::FOCUSSASH))
            score*=0.7
          end
          if attacker.hp*(1.0/attacker.totalhp)>0.1 && attacker.hp*(1.0/attacker.totalhp)<0.4
            score*=0.8
          end
        end
        ghostvar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:GHOST)
            ghostvar=true
          end
        end
        if move.id==(PBMoves::WILDCHARGE)
          if $fefieldeffect==18
            score*=1.1
            if ghostvar
              score*=0.8
            end
          end
        end
      when 0xFB # Wood Hammer
        if !(!attacker.abilitynulled && attacker.ability == PBAbilities::ROCKHEAD)
          score*=0.9
          if attacker.hp==attacker.totalhp && ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) || (attitemworks && attacker.item == PBItems::FOCUSSASH))
            score*=0.7
          end
          if attacker.hp*(1.0/attacker.totalhp)>0.15 && attacker.hp*(1.0/attacker.totalhp)<0.4
            score*=0.8
          end
        end
      when 0xFC # Head Smash
        if !(!attacker.abilitynulled && attacker.ability == PBAbilities::ROCKHEAD)
          score*=0.9
          if attacker.hp==attacker.totalhp && ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) || (attitemworks && attacker.item == PBItems::FOCUSSASH))
            score*=0.7
          end
          if attacker.hp*(1.0/attacker.totalhp)>0.2 && attacker.hp*(1.0/attacker.totalhp)<0.4
            score*=0.8
          end
        end
      when 0xFD # Volt Tackle
        if !(!attacker.abilitynulled && attacker.ability == PBAbilities::ROCKHEAD)
          score*=0.9
          if attacker.hp==attacker.totalhp && ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) || (attitemworks && attacker.item == PBItems::FOCUSSASH))
            score*=0.7
          end
          if attacker.hp*(1.0/attacker.totalhp)>0.15 && attacker.hp*(1.0/attacker.totalhp)<0.4
            score*=0.8
          end
        end
        if opponent.pbCanParalyze?(false)
          miniscore=100
          miniscore*=1.1
          miniscore*=1.3 if attacker.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
          if opponent.hp==opponent.totalhp
            miniscore*=1.2
          end
          ministat=0
          ministat+=opponent.stages[PBStats::ATTACK]
          ministat+=opponent.stages[PBStats::SPATK]
          ministat+=opponent.stages[PBStats::SPEED]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::NATURALCURE)
            miniscore*=0.3
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::MARVELSCALE)
            miniscore*=0.5
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::QUICKFEET) || (!opponent.abilitynulled && opponent.ability == PBAbilities::GUTS)
            miniscore*=0.2
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL) || roles.include?(PBMonRoles::PIVOT)
            miniscore*=1.2
          end
          if roles.include?(PBMonRoles::TANK)
            miniscore*=1.5
          end
          if pbRoughStat(opponent,PBStats::SPEED,skill)>attacker.pbSpeed && (pbRoughStat(opponent,PBStats::SPEED,skill)/2)<attacker.pbSpeed && @trickroom==0
            miniscore*=1.5
          end
          if pbRoughStat(opponent,PBStats::SPATK,skill)>pbRoughStat(opponent,PBStats::ATTACK,skill)
            miniscore*=1.3
          end
          count = -1
          sweepvar = false
          for i in pbParty(attacker.index)
            count+=1
            next if i.nil?
            temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
            if temprole.include?(PBMonRoles::SWEEPER)
              sweepvar = true
            end
          end
          miniscore*=1.3 if sweepvar
          if opponent.effects[PBEffects::Confusion]>0
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Attract]>=0
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SHEDSKIN)
            miniscore*=0.7
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SYNCHRONIZE) && attacker.status==0 && !attacker.pbHasType?(:ELECTRIC) && !attacker.pbHasType?(:GROUND)
            miniscore*=0.5
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
        end
      when 0xFE # Flare Blitz
        if !(!attacker.abilitynulled && attacker.ability == PBAbilities::ROCKHEAD)
          score*=0.9
          if attacker.hp==attacker.totalhp && ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) || (attitemworks && attacker.item == PBItems::FOCUSSASH))
            score*=0.7
          end
          if attacker.hp*(1.0/attacker.totalhp)>0.2 && attacker.hp*(1.0/attacker.totalhp)<0.4
            score*=0.8
          end
        end
        if opponent.pbCanBurn?(false)
          miniscore=100
          miniscore*=1.2
          ministat=0
          ministat+=opponent.stages[PBStats::ATTACK]
          ministat+=opponent.stages[PBStats::SPATK]
          ministat+=opponent.stages[PBStats::SPEED]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::NATURALCURE)
            miniscore*=0.3
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::MARVELSCALE)
            miniscore*=0.7
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::QUICKFEET) || (!opponent.abilitynulled && opponent.ability == PBAbilities::FLAREBOOST) || (!opponent.abilitynulled && opponent.ability == PBAbilities::MAGICGUARD)
            miniscore*=0.3
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::GUTS)
            miniscore*=0.1
          end
          miniscore*=0.3 if checkAImoves([PBMoves::FACADE],aimem)
          miniscore*=0.1 if checkAImoves([PBMoves::REST],aimem)
          if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
            miniscore*=1.7
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SYNCHRONIZE) && attacker.status==0
            miniscore*=0.5
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SHEDSKIN)
            miniscore*=0.7
          end
          if move.basedamage>0
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::STURDY)
              miniscore*=1.1
            end
          end
          miniscore-=100
          if move.addlEffect.to_f != 100
            miniscore*=(move.addlEffect.to_f/100)
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE)
              miniscore*=2
            end
          end
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
        end
      when 0xFF # Sunny Day
        if pbCheckGlobalAbility(:AIRLOCK) ||
          pbCheckGlobalAbility(:CLOUDNINE) ||
          pbCheckGlobalAbility(:DELTASTREAM) ||
          pbCheckGlobalAbility(:DESOLATELAND) ||
          pbCheckGlobalAbility(:PRIMORDIALSEA) ||
          pbWeather==PBWeather::SUNNYDAY
          score*=0
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          score*=1.3
        end
        if roles.include?(PBMonRoles::LEAD)
          score*=1.2
        end
        if (attitemworks && attacker.item == PBItems::HEATROCK)
          score*=1.3
        end
        if attacker.pbHasMove?((PBMoves::WEATHERBALL)) || (!attacker.abilitynulled && attacker.ability == PBAbilities::FORECAST)
          score*=2
        end
        if pbWeather!=0 && pbWeather!=PBWeather::SUNNYDAY
          score*=1.5
        end
        if attacker.pbHasMove?((PBMoves::MOONLIGHT)) || attacker.pbHasMove?((PBMoves::SYNTHESIS)) || attacker.pbHasMove?((PBMoves::MORNINGSUN)) || attacker.pbHasMove?((PBMoves::GROWTH)) || attacker.pbHasMove?((PBMoves::SOLARBEAM)) || attacker.pbHasMove?((PBMoves::SOLARBLADE))
          score*=1.5
        end
        if attacker.pbHasType?(:FIRE)
          score*=1.5
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CHLOROPHYLL) || (!attacker.abilitynulled && attacker.ability == PBAbilities::FLOWERGIFT)
          score*=2
          if (attitemworks && attacker.item == PBItems::FOCUSSASH)
            score*=2
          end
          if attacker.effects[PBEffects::KingsShield]== true ||
          attacker.effects[PBEffects::BanefulBunker]== true ||
          attacker.effects[PBEffects::SpikyShield]== true
            score *=3
          end
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SOLARPOWER) || (!attacker.abilitynulled && attacker.ability == PBAbilities::LEAFGUARD)
          score*=1.3
        end
        watervar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:WATER)
            watervar=true
          end
        end
        if watervar
          score*=0.5
        end
        if attacker.pbHasMove?((PBMoves::THUNDER)) || attacker.pbHasMove?((PBMoves::HURRICANE))
          score*=0.7
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::DRYSKIN)
          score*=0.5
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::HARVEST)
          score*=1.5
        end
        if pbWeather==PBWeather::RAINDANCE
          miniscore = getFieldDisruptScore(attacker,opponent,skill)
          if attacker.pbHasType?(:NORMAL)
            miniscore*=1.2
          end
          score*=miniscore
        end
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==12 || $fefieldeffect==27 || $fefieldeffect==28 # Desert/Mountian/Snowy Mountain
            score*=1.3
          end
          if $fefieldeffect==33 # Flower Garden
            score*=2
          end
          if $fefieldeffect==4 # Dark Crystal
            darkvar=false
            for mon in pbParty(attacker.index)
              next if mon.nil?
              if mon.hasType?(:DARK)
                darkvar=true
              end
            end
            if !darkvar
              score*=3
            end
          end
          if $fefieldeffect==22 || $fefieldeffect==35 # Underwater or New World
            score*=0
          end
        end
      when 0x100 # Rain Dance
        if pbCheckGlobalAbility(:AIRLOCK) ||
          pbCheckGlobalAbility(:CLOUDNINE) ||
          pbCheckGlobalAbility(:DELTASTREAM) ||
          pbCheckGlobalAbility(:DESOLATELAND) ||
          pbCheckGlobalAbility(:PRIMORDIALSEA) ||
          pbWeather==PBWeather::RAINDANCE
          score*=0
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          score*=1.3
        end
        if roles.include?(PBMonRoles::LEAD)
          score*=1.2
        end
        if (attitemworks && attacker.item == PBItems::DAMPROCK)
          score*=1.3
        end
        if attacker.pbHasMove?((PBMoves::WEATHERBALL)) || (!attacker.abilitynulled && attacker.ability == PBAbilities::FORECAST)
          score*=2
        end
        if pbWeather!=0 && pbWeather!=PBWeather::RAINDANCE
          score*=1.3
        end
        if attacker.pbHasMove?((PBMoves::THUNDER)) || attacker.pbHasMove?((PBMoves::HURRICANE))
          score*=1.5
        end
        if attacker.pbHasType?(:WATER)
          score*=1.5
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SWIFTSWIM)
          score*=2
          if (attitemworks && attacker.item == PBItems::FOCUSSASH)
            score*=2
          end
          if attacker.effects[PBEffects::KingsShield]== true ||
          attacker.effects[PBEffects::BanefulBunker]== true ||
          attacker.effects[PBEffects::SpikyShield]== true
            score *=3
          end
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::DRYSKIN) || pbWeather==PBWeather::RAINDANCE
          score*=1.5
        end
        if pbWeather==PBWeather::SUNNYDAY
          miniscore = getFieldDisruptScore(attacker,opponent,skill)
          if attacker.pbHasType?(:NORMAL)
            miniscore*=1.2
          end
          score*=miniscore
        end
        firevar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:FIRE)
            firevar=true
          end
        end
        if firevar
          score*=0.5
        end
        if attacker.pbHasMove?((PBMoves::MOONLIGHT)) || attacker.pbHasMove?((PBMoves::SYNTHESIS)) || attacker.pbHasMove?((PBMoves::MORNINGSUN)) || attacker.pbHasMove?((PBMoves::GROWTH)) || attacker.pbHasMove?((PBMoves::SOLARBEAM)) || attacker.pbHasMove?((PBMoves::SOLARBLADE))
          score*=0.5
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::HYDRATION)
          score*=1.5
        end
        if @opponent.is_a?(Array) == false
          if (@opponent.trainertype==PBTrainers::SHELLY || @opponent.trainertype==PBTrainers::BENNETTLAURA) && # Shelly / Laura
          ($fefieldeffect == 2 || $fefieldeffect == 15 || $fefieldeffect == 33)
            score *= 3.5
            #experimental -- cancels out drop if killing moves
            if initialscores.length>0
              score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
            end
            #end experimental
          end
        end
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==6 # Big Top
            score*=1.2
          end
          if $fefieldeffect==2 || $fefieldeffect==15 || $fefieldeffect==16 # Grassy/Forest/Superheated
            score*=1.5
          end
          if $fefieldeffect==7 || $fefieldeffect==33 # Burning/Flower Garden
            score*=2
          end
          if $fefieldeffect==34 # Starlight
            darkvar=false
            fairyvar=false
            psychicvar=false
            for mon in pbParty(attacker.index)
              next if mon.nil?
              if mon.hasType?(:DARK)
                darkvar=true
              end
              if mon.hasType?(:FAIRY)
                fairyvar=true
              end
              if mon.hasType?(:PSYCHIC)
                psychicvar=true
              end
            end
            if !darkvar && !fairyvar && !psychicvar
              score*=2
            end
          end
          if $fefieldeffect==22 || $fefieldeffect==35 # Underwater or New World
            score*=0
          end
        end
      when 0x101 # Sandstorm
        if pbCheckGlobalAbility(:AIRLOCK) ||
          pbCheckGlobalAbility(:CLOUDNINE) ||
          pbCheckGlobalAbility(:DELTASTREAM) ||
          pbCheckGlobalAbility(:DESOLATELAND) ||
          pbCheckGlobalAbility(:PRIMORDIALSEA) ||
          pbWeather==PBWeather::SANDSTORM
          score*=0
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          score*=1.3
        end
        if roles.include?(PBMonRoles::LEAD)
          score*=1.2
        end
        if (attitemworks && attacker.item == PBItems::SMOOTHROCK)
          score*=1.3
        end
        if attacker.pbHasMove?((PBMoves::WEATHERBALL)) || (!attacker.abilitynulled && attacker.ability == PBAbilities::FORECAST)
          score*=2
        end
        if pbWeather!=0 && pbWeather!=PBWeather::SANDSTORM
          score*=2
        end
        if attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)
          score*=1.3
        else
          score*=0.7
        end
        if attacker.pbHasType?(:ROCK)
          score*=1.5
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SANDRUSH)
          score*=2
          if (attitemworks && attacker.item == PBItems::FOCUSSASH)
            score*=2
          end
          if attacker.effects[PBEffects::KingsShield]== true ||
          attacker.effects[PBEffects::BanefulBunker]== true ||
          attacker.effects[PBEffects::SpikyShield]== true
            score *=3
          end
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SANDVEIL)
          score*=1.3
        end
        if attacker.pbHasMove?((PBMoves::MOONLIGHT)) || attacker.pbHasMove?((PBMoves::SYNTHESIS)) || attacker.pbHasMove?((PBMoves::MORNINGSUN)) || attacker.pbHasMove?((PBMoves::GROWTH)) || attacker.pbHasMove?((PBMoves::SOLARBEAM)) || attacker.pbHasMove?((PBMoves::SOLARBLADE))
          score*=0.5
        end
        if attacker.pbHasMove?((PBMoves::SHOREUP))
          score*=1.5
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SANDFORCE)
          score*=1.5
        end
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==20 || $fefieldeffect==12 # Ashen Beach/Desert
            score*=1.3
          end
          if $fefieldeffect==9 # Rainbow
            score*=1.5
          end
          if $fefieldeffect==7 # Burning
            score*=3
          end
          if $fefieldeffect==34 # Starlight
            darkvar=false
            fairyvar=false
            psychicvar=false
            for mon in pbParty(attacker.index)
              next if mon.nil?
              if mon.hasType?(:DARK)
                darkvar=true
              end
              if mon.hasType?(:FAIRY)
                fairyvar=true
              end
              if mon.hasType?(:PSYCHIC)
                psychicvar=true
              end
            end
            if !darkvar && !fairyvar && !psychicvar
              score*=2
            end
          end
          if $fefieldeffect==22 || $fefieldeffect==35 # Underwater or New World
            score*=0
          end
        end
      when 0x102 # Hail
        if pbCheckGlobalAbility(:AIRLOCK) ||
          pbCheckGlobalAbility(:CLOUDNINE) ||
          pbCheckGlobalAbility(:DELTASTREAM) ||
          pbCheckGlobalAbility(:DESOLATELAND) ||
          pbCheckGlobalAbility(:PRIMORDIALSEA) ||
          pbWeather==PBWeather::HAIL
          score*=0
        end
        if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
          score*=1.3
        end
        if roles.include?(PBMonRoles::LEAD)
          score*=1.2
        end
        if (attitemworks && attacker.item == PBItems::ICYROCK)
          score*=1.3
        end
        if attacker.pbHasMove?((PBMoves::WEATHERBALL)) || (!attacker.abilitynulled && attacker.ability == PBAbilities::FORECAST)
          score*=2
        end
        if pbWeather!=0 && pbWeather!=PBWeather::HAIL
          score*=1.3
        end
        if attacker.pbHasType?(:ICE)
          score*=5
        else
          score*=0.7
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SLUSHRUSH)
          score*=2
          if (attitemworks && attacker.item == PBItems::FOCUSSASH)
            score*=2
          end
          if attacker.effects[PBEffects::KingsShield]== true ||
          attacker.effects[PBEffects::BanefulBunker]== true ||
          attacker.effects[PBEffects::SpikyShield]== true
            score *=3
          end
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SNOWCLOAK) || (!attacker.abilitynulled && attacker.ability == PBAbilities::ICEBODY)
          score*=1.3
        end
        if attacker.pbHasMove?((PBMoves::MOONLIGHT)) || attacker.pbHasMove?((PBMoves::SYNTHESIS)) || attacker.pbHasMove?((PBMoves::MORNINGSUN)) || attacker.pbHasMove?((PBMoves::GROWTH)) || attacker.pbHasMove?((PBMoves::SOLARBEAM)) || attacker.pbHasMove?((PBMoves::SOLARBLADE))
          score*=0.5
        end
        if attacker.pbHasMove?((PBMoves::AURORAVEIL))
          score*=2
        end
        if attacker.pbHasMove?((PBMoves::BLIZZARD))
          score*=1.3
        end
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==13 || $fefieldeffect==28 # Icy/Snowy Mountain
            score*=1.2
          end
          if $fefieldeffect==9 || $fefieldeffect==27 # Rainbow/Mountian
            score*=1.5
          end
          if $fefieldeffect==16 # Superheated
            score*=0
          end
          if $fefieldeffect==34 # Starlight
            darkvar=false
            fairyvar=false
            psychicvar=false
            for mon in pbParty(attacker.index)
              next if mon.nil?
              if mon.hasType?(:DARK)
                darkvar=true
              end
              if mon.hasType?(:FAIRY)
                fairyvar=true
              end
              if mon.hasType?(:PSYCHIC)
                psychicvar=true
              end
            end
            if !darkvar && !fairyvar && !psychicvar
              score*=2
            end
          end
          if $fefieldeffect==22 || $fefieldeffect==35 # Underwater or New World
            score*=0
          end
        end
      when 0x103 # Spikes
        if attacker.pbOpposingSide.effects[PBEffects::Spikes]!=3
          if roles.include?(PBMonRoles::LEAD)
            score*=1.1
          end
          if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
            score*=1.1
          end
          if attacker.turncount<2
            score*=1.2
          end
          livecount1=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount1+=1 if i.hp!=0
          end
          livecount2=0
          for i in pbParty(attacker.index)
            next if i.nil?
            livecount2+=1 if i.hp!=0
          end
          if livecount1>3
            miniscore=(livecount1-1)
            miniscore*=0.2
            score*=miniscore
          else
            score*=0.1
          end
          if attacker.pbOpposingSide.effects[PBEffects::Spikes]>0
            score*=0.9
          end
          if skill>=PBTrainerAI.bestSkill
            for k in 0...pbParty(opponent.index).length
              next if pbParty(opponent.index)[k].nil?
              if @aiMoveMemory[2][k].length>0
                movecheck=false
                for j in @aiMoveMemory[2][k]
                  movecheck=true if j.id==(PBMoves::DEFOG) || j.id==(PBMoves::RAPIDSPIN)
                end
                score*=0.3 if movecheck
              end
            end
          elsif skill>=PBTrainerAI.mediumSkill
            score*=0.3 if checkAImoves([PBMoves::DEFOG,PBMoves::RAPIDSPIN],aimem)
          end
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==21 || $fefieldeffect==26 # (Murk)Water Surface
              score*=0
            end
          end
        else
          score*=0
        end
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==19 # Wasteland
            score = ((opponent.totalhp/3.0)/opponent.hp)*100
            score*=1.5 if @doublebattle
          end
        end
      when 0x104 # Toxic Spikes
        if attacker.pbOpposingSide.effects[PBEffects::ToxicSpikes]!=2
          if roles.include?(PBMonRoles::LEAD)
            score*=1.1
          end
          if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
            score*=1.1
          end
          if attacker.turncount<2
            score*=1.2
          end
          livecount1=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount1+=1 if i.hp!=0
          end
          livecount2=0
          for i in pbParty(attacker.index)
            next if i.nil?
            livecount2+=1 if i.hp!=0
          end
          if livecount1>3
            miniscore=(livecount1-1)
            miniscore*=0.2
            score*=miniscore
          else
            score*=0.1
          end
          if attacker.pbOpposingSide.effects[PBEffects::ToxicSpikes]>0
            score*=0.9
          end
          if skill>=PBTrainerAI.bestSkill
            for k in 0...pbParty(opponent.index).length
              next if pbParty(opponent.index)[k].nil?
              if @aiMoveMemory[2][k].length>0
                movecheck=false
                for j in @aiMoveMemory[2][k]
                  movecheck=true if j.id==(PBMoves::DEFOG) || j.id==(PBMoves::RAPIDSPIN)
                end
                score*=0.3 if movecheck
              end
            end
          elsif skill>=PBTrainerAI.mediumSkill
            score*=0.3 if checkAImoves([PBMoves::DEFOG,PBMoves::RAPIDSPIN],aimem)
          end
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==21 || $fefieldeffect==26 # (Murk)Water Surface
              score*=0
            end
            if $fefieldeffect==10 # Corrosive
              score*=1.2
            end
          end
        else
          score*=0
        end
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==19 # Wasteland
            score = ((opponent.totalhp*0.13)/opponent.hp)*100
            if opponent.pbCanPoison?(false)
              score*=1.5
            else
              score*=0
            end
            score*=1.5 if @doublebattle
            if opponent.hasType?(:POISON)
              score*=0
            end
          end
        end
      when 0x105 # Stealth Rock
        if !attacker.pbOpposingSide.effects[PBEffects::StealthRock]
          if roles.include?(PBMonRoles::LEAD)
            score*=1.1
          end
          if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
            score*=1.4
          end
          if attacker.turncount<2
            score*=1.3
          end
          livecount1=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount1+=1 if i.hp!=0
          end
          livecount2=0
          for i in pbParty(attacker.index)
            next if i.nil?
            livecount2+=1 if i.hp!=0
          end
          if livecount1>3
            miniscore=(livecount1-1)
            miniscore*=0.2
            score*=miniscore
          else
            score*=0.1
          end
          if skill>=PBTrainerAI.bestSkill
            for k in 0...pbParty(opponent.index).length
              next if pbParty(opponent.index)[k].nil?
              if @aiMoveMemory[2][k].length>0
                movecheck=false
                for j in @aiMoveMemory[2][k]
                  movecheck=true if j.id==(PBMoves::DEFOG) || j.id==(PBMoves::RAPIDSPIN)
                end
                score*=0.3 if movecheck
              end
            end
          elsif skill>=PBTrainerAI.mediumSkill
            score*=0.3 if checkAImoves([PBMoves::DEFOG,PBMoves::RAPIDSPIN],aimem)
          end
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect==23 || $fefieldeffect==14 # Cave/Rocky
              score*=2
            end
            if $fefieldeffect==25 # Crystal Cavern
              score*=1.3
            end
          end
        else
          score*=0
        end
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==19 # Wasteland
            atype=(PBTypes::ROCK)
            score = ((opponent.totalhp/4.0)/opponent.hp)*100
            score*=2 if pbTypeModNoMessages(atype,attacker,opponent,move,skill)>4
            score*=1.5 if @doublebattle
          end
        end
      when 0x106 # Grass Pledge
        if $fepledgefield != 3
          miniscore = getFieldDisruptScore(attacker,opponent,skill)
          if $fepledgefield!=1 && $fepledgefield!=2
            miniscore*=0.7
          else
            firevar=false
            for mon in pbParty(attacker.index)
              next if mon.nil?
              if mon.hasType?(:FIRE)
                firevar=true
              end
            end
            if $fepledgefield==1
              if attacker.pbHasType?(:FIRE)
                miniscore*=1.4
              else
                miniscore*=0.3
              end
              if opponent.pbHasType?(:FIRE)
                miniscore*=0.3
              else
                miniscore*=1.4
              end
              if firevar
                miniscore*=1.4
              else
                miniscore*=1.3
              end
            end
          end
          score*=miniscore
        end
      when 0x107 # Fire Pledge
        firevar=false
        poisonvar=false
        bugvar=false
        grassvar=false
        icevar=false
        poisonvar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:FIRE)
            firevar=true
          end
          if mon.hasType?(:POISON)
            poisonvar=true
          end
          if mon.hasType?(:BUG)
            bugvar=true
          end
          if mon.hasType?(:GRASS)
            grassvar=true
          end
          if mon.hasType?(:ICE)
            icevar=true
          end
          if mon.hasType?(:POISON)
            poisonvar=true
          end
        end
        if $fepledgefield != 1
          miniscore = getFieldDisruptScore(attacker,opponent,skill)
          if $fepledgefield!=3 && $fepledgefield!=2
            miniscore*=0.7
          else
            if $fepledgefield==3
              if attacker.pbHasType?(:FIRE)
                miniscore*=1.4
              else
                miniscore*=0.3
              end
              if opponent.pbHasType?(:FIRE)
                miniscore*=0.3
              else
                miniscore*=1.4
              end
              if firevar
                miniscore*=1.4
              else
                miniscore*=1.3
              end
            end
            if $fepledgefield==2
              miniscore*=1.2
              if attacker.pbHasType?(:NORMAL)
                miniscore*=1.2
              end
            end
          end
          score*=miniscore
        end
        if $fefieldeffect==2 || $fefieldeffect==15 || ($fefieldeffect==33 && $fecounter>1)
          if firevar && !(bugvar || grassvar)
            score*=2
          end
        elsif $fefieldeffect==16
          if firevar
            score*=2
          end
        elsif $fefieldeffect==11
          if !poisonvar
            score*=1.1
          end
          if attacker.hp*5<attacker.totalhp
            score*=2
          end
          if opponent.pbNonActivePokemonCount==0
            score*=5
          end
        elsif $fefieldeffect==13 || $fefieldeffect==28
          if !icevar
            score*=1.5
          end
        end
      when 0x108 # Water Pledge
        if $fepledgefield != 2
          miniscore = getFieldDisruptScore(attacker,opponent,skill)
          if $fepledgefield!=1 && $fepledgefield!=3
            miniscore*=0.7
          else
            firevar=false
            for mon in pbParty(attacker.index)
              next if mon.nil?
              if mon.hasType?(:FIRE)
                firevar=true
              end
            end
            if $fepledgefield==1
              miniscore*=1.2
              if attacker.pbHasType?(:NORMAL)
                miniscore*=1.2
              end
            end
          end
          score*=miniscore
        end
        if $fefieldeffect==7
          if firevar
            score*=0
          else
            score*=2
          end
        end
      when 0x109 # Pay Day
      when 0x10A # Brick Break
        if attacker.pbOpposingSide.effects[PBEffects::Reflect]>0
          score*=1.8
        end
        if attacker.pbOpposingSide.effects[PBEffects::LightScreen]>0
          score*=1.3
        end
        if attacker.pbOpposingSide.effects[PBEffects::AuroraVeil]>0
          score*=2.0
        end
      when 0x10B # Hi Jump Kick
        if score < 100
          score *= 0.8
        end
        score*=0.5 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
        ministat=opponent.stages[PBStats::EVASION]
        ministat*=(-10)
        ministat+=100
        ministat/=100.0
        score*=ministat
        ministat=attacker.stages[PBStats::ACCURACY]
        ministat*=(10)
        ministat+=100
        ministat/=100.0
        score*=ministat
        if ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) || ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL)
          score*=0.7
        end
        if (oppitemworks && opponent.item == PBItems::LAXINCENSE) || (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER)
          score*=0.7
        end
        if attacker.index != 2
          if skill>=PBTrainerAI.bestSkill
            if $fefieldeffect!=36
              ghostvar = false
              for mon in pbParty(opponent.index)
                next if mon.nil?
                ghostvar=true if mon.hasType?(:GHOST)
              end
              if ghostvar
                score*=0.5
              end
            end
          end
        end
      when 0x10C # Substitute
        if attacker.hp*4>attacker.totalhp
          if attacker.effects[PBEffects::Substitute]>0
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=0
            else
              if opponent.effects[PBEffects::LeechSeed]<0
                score*=0
              end
            end
          else
            if attacker.hp==attacker.totalhp
              score*=1.1
            else
              score*= (attacker.hp*(1.0/attacker.totalhp))
            end
            if opponent.effects[PBEffects::LeechSeed]>=0
              score*=1.2
            end
            if (attitemworks && attacker.item == PBItems::LEFTOVERS)
              score*=1.2
            end
            for j in attacker.moves
              if j.isHealingMove?
                score*=1.2
                break
              end
            end
            if opponent.pbHasMove?((PBMoves::SPORE)) || opponent.pbHasMove?((PBMoves::SLEEPPOWDER))
              score*=1.2
            end
            if attacker.pbHasMove?((PBMoves::FOCUSPUNCH))
              score*=1.5
            end
            if opponent.status==PBStatuses::SLEEP
              score*=1.5
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::INFILTRATOR)
              score*=0.3
            end
            if opponent.pbHasMove?((PBMoves::UPROAR)) || opponent.pbHasMove?((PBMoves::HYPERVOICE)) || opponent.pbHasMove?((PBMoves::ECHOEDVOICE)) || opponent.pbHasMove?((PBMoves::SNARL)) || opponent.pbHasMove?((PBMoves::BUGBUZZ)) || opponent.pbHasMove?((PBMoves::BOOMBURST))
              score*=0.3
            end
            score*=2 if checkAIdamage(aimem,attacker,opponent,skill)*4<attacker.totalhp && (aimem.length > 0)
            if opponent.effects[PBEffects::Confusion]>0
              score*=1.3
            end
            if opponent.status==PBStatuses::PARALYSIS
              score*=1.3
            end
            if opponent.effects[PBEffects::Attract]>=0
              score*=1.3
            end
            if attacker.pbHasMove?((PBMoves::BATONPASS))
              score*=1.2
            end
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SPEEDBOOST)
              score*=1.1
            end
            if @doublebattle
              score*=0.5
            end
          end
        else
          score*=0
        end
      when 0x10D # Curse
        if attacker.pbHasType?(:GHOST)
          if opponent.effects[PBEffects::Curse] || attacker.hp*2<attacker.totalhp
            score*=0
          else
            score*=0.7
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=0.5
            end
            if checkAIdamage(aimem,attacker,opponent,skill)*5 < attacker.hp && (aimem.length > 0)
              score*=1.3
            end
            for j in attacker.moves
              if j.isHealingMove?
                score*=1.2
                break
              end
            end
            ministat= 5*statchangecounter(opponent,1,7)
            ministat+=100
            ministat/=100.0
            score*=ministat
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || (!attacker.abilitynulled && attacker.ability == PBAbilities::ARENATRAP) || opponent.effects[PBEffects::MeanLook]>=0 ||  opponent.pbNonActivePokemonCount==0
              score*=1.3
            else
              score*=0.8
            end
            if @doublebattle
              score*=0.5
            end
            if initialscores.length>0
              score*=1.3 if hasbadmoves(initialscores,scoreindex,25)
            end
            if $fefieldeffect==29
              score*=0
            end
          end
        else
          miniscore=100
          if attacker.effects[PBEffects::Substitute]>0 || attacker.effects[PBEffects::Disguise]
            miniscore*=1.3
          end
          if initialscores.length>0
            miniscore*=1.3 if hasbadmoves(initialscores,scoreindex,20)
          end
          if (attacker.hp.to_f)/attacker.totalhp>0.75
            miniscore*=1.2
          end
          if (attacker.hp.to_f)/attacker.totalhp<0.33
            miniscore*=0.3
          end
          if (attacker.hp.to_f)/attacker.totalhp<0.75 && ((!attacker.abilitynulled && attacker.ability == PBAbilities::EMERGENCYEXIT) || (!attacker.abilitynulled && attacker.ability == PBAbilities::WIMPOUT) || (attitemworks && attacker.item == PBItems::EJECTBUTTON))
            miniscore*=0.3
          end
          if attacker.pbOpposingSide.effects[PBEffects::Retaliate]
            miniscore*=0.3
          end
          if opponent.effects[PBEffects::HyperBeam]>0
            miniscore*=1.3
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=1.7
          end
          if checkAIdamage(aimem,attacker,opponent,skill)<(attacker.hp/4.0) && (aimem.length > 0)
            miniscore*=1.2
          elsif checkAIdamage(aimem,attacker,opponent,skill)>(attacker.hp/2.0)
            miniscore*=0.3
          end
          if attacker.turncount<2
            miniscore*=1.1
          end
          if opponent.status!=0
            miniscore*=1.2
          end
          if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
            miniscore*=1.3
          end
          if opponent.effects[PBEffects::Encore]>0
            if opponent.moves[(opponent.effects[PBEffects::EncoreIndex])].basedamage==0
              miniscore*=1.5
            end
          end
          if attacker.effects[PBEffects::Confusion]>0
            miniscore*=0.3
          end
          if attacker.effects[PBEffects::LeechSeed]>=0 || attacker.effects[PBEffects::Attract]>=0
            miniscore*=0.3
          end
          score*=0.3 if checkAImoves(PBStuff::SWITCHOUTMOVE,aimem)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::SIMPLE)
            miniscore*=2
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
            miniscore*=0.5
          end
          if @doublebattle
            miniscore*=0.5
          end
          if attacker.stages[PBStats::SPEED]<0
            ministat=attacker.stages[PBStats::SPEED]
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          ministat=0
          ministat+=opponent.stages[PBStats::ATTACK]
          ministat+=opponent.stages[PBStats::SPATK]
          ministat+=opponent.stages[PBStats::SPEED]
          if ministat>0
            minimini=(-5)*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          miniscore/=100.0
          score*=miniscore
          miniscore=100
          miniscore*=1.3 if checkAIhealing(aimem)
          if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
            miniscore*=0.5
          else
            miniscore*=1.1
          end
          if attacker.status==PBStatuses::BURN
            miniscore*=0.5
          end
          if attacker.status==PBStatuses::PARALYSIS
            miniscore*=0.5
          end
          miniscore*=0.8 if checkAImoves([PBMoves::FOULPLAY],aimem)
          physmove=false
          for j in attacker.moves
            if j.pbIsPhysical?(j.type)
              physmove=true
            end
          end
          if physmove && !attacker.pbTooHigh?(PBStats::ATTACK)
            miniscore/=100.0
            score*=miniscore
          end
          miniscore=100
          if attacker.effects[PBEffects::Toxic]>0
            miniscore*=0.2
          end
          if pbRoughStat(opponent,PBStats::SPATK,skill)<pbRoughStat(opponent,PBStats::ATTACK,skill)
            if !(roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL))
              if ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && (attacker.hp.to_f)/attacker.totalhp>0.75
                miniscore*=1.3
              elsif (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
                miniscore*=0.7
              end
            end
            miniscore*=1.3
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            miniscore*=1.1
          end
          if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
            miniscore*=1.1
          end
          healmove=false
          for j in attacker.moves
            if j.isHealingMove?
              healmove=true
            end
          end
          if healmove
            miniscore*=1.2
          end
          if attacker.pbHasMove?((PBMoves::LEECHSEED))
            miniscore*=1.3
          end
          if attacker.pbHasMove?((PBMoves::PAINSPLIT))
            miniscore*=1.2
          end
          if !attacker.pbTooHigh?(PBStats::DEFENSE)
            miniscore/=100.0
            score*=miniscore
          end
          if (opponent.level-5)>attacker.level
            score*=0.6
            if (opponent.level-10)>attacker.level
              score*=0.2
            end
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            score=0
          end
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=0.7
          end
          if attacker.pbTooHigh?(PBStats::DEFENSE) && attacker.pbTooHigh?(PBStats::ATTACK)
            score *= 0
          end
        end
      when 0x10E # Spite
        count=0
        for i in opponent.moves
          if i.basedamage>0
            count+=1
          end
        end
        lastmove = PBMove.new(opponent.lastMoveUsed)
        if lastmove.basedamage>0 && count==1
          score+=10
        end
        if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=0.5
        end
        if lastmove.totalpp==5
          score*=1.5
        else
          if lastmove.totalpp==10
            score*=1.2
          else
            score*=0.7
          end
        end
      when 0x10F # Nightmare
        if !opponent.effects[PBEffects::Nightmare] && opponent.status==PBStatuses::SLEEP && opponent.effects[PBEffects::Substitute]<=0
          if opponent.statusCount>2
            score*=4
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::EARLYBIRD)
            score*=0.5
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::COMATOSE)
            score*=6
          end
          if initialscores.length>0
            score*=6 if hasbadmoves(initialscores,scoreindex,25)
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SHEDSKIN)
            score*=0.5
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || (!attacker.abilitynulled && attacker.ability == PBAbilities::ARENATRAP) || opponent.effects[PBEffects::MeanLook]>=0 ||  opponent.pbNonActivePokemonCount==0
            score*=1.3
          else
            score*=0.8
          end
          if @doublebattle
            score*=0.5
          end
          if $fefieldeffect==9
            score*=0
          end
        else
          score*=0
        end
      when 0x110 # Rapid Spin
        if attacker.effects[PBEffects::LeechSeed]>=0
          score+=20
        end
        if attacker.effects[PBEffects::MultiTurn]>0
          score+=10
        end
        if attacker.pbNonActivePokemonCount>0
          score+=25 if attacker.pbOwnSide.effects[PBEffects::StealthRock]
          score+=25 if attacker.pbOwnSide.effects[PBEffects::StickyWeb]
          score += (10*attacker.pbOwnSide.effects[PBEffects::Spikes])
          score += (15*attacker.pbOwnSide.effects[PBEffects::ToxicSpikes])
        end
      when 0x111 # Future Sight
        whichdummy = 0
        if move.id == 516
          whichdummy = 637
        elsif move.id == 450
          whichdummy = 636
        end
        dummydata = PBMove.new(whichdummy)
        dummymove = PokeBattle_Move.pbFromPBMove(self,dummydata)
        tempdam=pbRoughDamage(dummymove,attacker,opponent,skill,dummymove.basedamage)
        dummydam=(tempdam*100)/(opponent.hp.to_f)
        dummydam=110 if dummydam>110
        score = pbGetMoveScore(dummymove,attacker,opponent,skill,dummydam)
        if opponent.effects[PBEffects::FutureSight]>0
          score*=0
        else
          score*=0.6
          if @doublebattle
            score*=0.7
          end
          if attacker.pbNonActivePokemonCount==0
            score*=0.7
          end
          if attacker.effects[PBEffects::Substitute]>0
            score*=1.2
          end
          protectmove=false
          for j in attacker.moves
            protectmove = true if j.id==(PBMoves::PROTECT) || j.id==(PBMoves::DETECT) || j.id==(PBMoves::BANEFULBUNKER) || j.id==(PBMoves::SPIKYSHIELD)
          end
          if protectmove
            score*=1.2
          end
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            score*=1.1
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::MOODY) || attacker.pbHasMove?((PBMoves::QUIVERDANCE)) || attacker.pbHasMove?((PBMoves::NASTYPLOT)) || attacker.pbHasMove?((PBMoves::TAILGLOW))
            score*=1.2
          end
        end
      when 0x112 # Stockpile
        miniscore=100
        if attacker.effects[PBEffects::Substitute]>0 || attacker.effects[PBEffects::Disguise]
          miniscore*=1.3
        end
        if initialscores.length>0
          miniscore*=1.3 if hasbadmoves(initialscores,scoreindex,20)
        end
        if (attacker.hp.to_f)/attacker.totalhp>0.75
          miniscore*=1.1
        end
        if opponent.effects[PBEffects::HyperBeam]>0
          miniscore*=1.2
        end
        if opponent.effects[PBEffects::Yawn]>0
          miniscore*=1.3
        end
        if skill>=PBTrainerAI.mediumSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if maxdam<(attacker.hp/4.0) && (aimem.length > 0)
            miniscore*=1.1
          else
            if move.basedamage==0
              miniscore*=0.8
              if maxdam>attacker.hp
                miniscore*=0.1
              end
            end
          end
        end
        if attacker.turncount<2
          miniscore*=1.1
        end
        if opponent.status!=0
          miniscore*=1.1
        end
        if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
          miniscore*=1.3
        end
        if opponent.effects[PBEffects::Encore]>0
          if opponent.moves[(opponent.effects[PBEffects::EncoreIndex])].basedamage==0
            miniscore*=1.5
          end
        end
        if attacker.effects[PBEffects::Confusion]>0
          miniscore*=0.5
        end
        if attacker.effects[PBEffects::LeechSeed]>=0 || attacker.effects[PBEffects::Attract]>=0
          miniscore*=0.3
        end
        if attacker.effects[PBEffects::Toxic]>0
          miniscore*=0.2
        end
        miniscore*=0.2 if checkAImoves(PBStuff::SWITCHOUTMOVE,aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SIMPLE)
          miniscore*=2
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=0.5
        end
        if @doublebattle
          miniscore*=0.3
        end
        if skill>=PBTrainerAI.mediumSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if (maxdam.to_f/attacker.hp)<0.12 && (aimem.length > 0)
            miniscore*=0.3
          end
        end
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.5
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.7
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        if attacker.pbHasMove?((PBMoves::SPITUP)) || attacker.pbHasMove?((PBMoves::SWALLOW))
          miniscore*=1.6
        end
        if attacker.effects[PBEffects::Stockpile]<3
          miniscore/=100.0
          score*=miniscore
        else
          score=0
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score=0
        end
        if attacker.pbTooHigh?(PBStats::SPDEF) && attacker.pbTooHigh?(PBStats::DEFENSE)
          score*=0
        end
      when 0x113 # Spit Up
        startscore = score
        if attacker.effects[PBEffects::Stockpile]==0
          score*=0
        else
          score*=0.8
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            score*=0.7
          end
          if roles.include?(PBMonRoles::TANK)
            score*=0.9
          end
          count=0
          for m in attacker.moves
            count+=1 if m.basedamage>0
          end
          if count>1
            score*=0.5
          end
          if opponent.pbNonActivePokemonCount==0
            score*=0.7
          else
            score*=1.2
          end
          if startscore < 110
            score*=0.5
          else
            score*=1.3
          end
          if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.1
          else
            score*=0.8
          end
          if attacker.pbHasMove?((PBMoves::SWALLOW))
            if attacker.hp/(attacker.totalhp.to_f) < 0.66
              score*=0.8
              if attacker.hp/(attacker.totalhp.to_f) < 0.4
                score*=0.5
              end
            end
          end
        end
      when 0x114 # Swallow
        startscore = score
        if attacker.effects[PBEffects::Stockpile]==0
          score*=0
        else
          score+= 10*attacker.effects[PBEffects::Stockpile]
          score*=0.8
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            score*=0.9
          end
          if roles.include?(PBMonRoles::TANK)
            score*=0.9
          end
          count=0
          for m in attacker.moves
            count+=1 if m.isHealingMove?
          end
          if count>1
            score*=0.5
          end
          if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.1
          else
            score*=0.8
          end
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=2
          elsif checkAIdamage(aimem,attacker,opponent,skill)*1.5 > attacker.hp
            score*=1.5
          end
          if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            if checkAIdamage(aimem,attacker,opponent,skill)*2 > attacker.hp
              score*=2
            else
              score*=0.2
            end
          end
          score*=0.7 if checkAImoves(PBStuff::SETUPMOVE,aimem)
          if attacker.hp*2 < attacker.totalhp
            score*=1.5
          end
          if attacker.status==PBStatuses::BURN || attacker.status==PBStatuses::POISON || attacker.effects[PBEffects::Curse] || attacker.effects[PBEffects::LeechSeed]>=0
            score*=1.3
            if attacker.effects[PBEffects::Toxic]>0
              score*=1.3
            end
          end
          if opponent.effects[PBEffects::HyperBeam]>0
            score*=1.2
          end
          if attacker.hp/(attacker.totalhp.to_f) > 0.8
            score*=0
          end
        end
      when 0x115 # Focus Punch
        startscore=score
        soundcheck=false
        multicheck=false
        if aimem.length > 0
          for j in aimem
            soundcheck=true if (j.isSoundBased? && j.basedamage>0)
            multicheck=true if j.pbNumHits(opponent)>1
          end
        end
        if attacker.effects[PBEffects::Substitute]>0
          if multicheck || soundcheck || (!opponent.abilitynulled && opponent.ability == PBAbilities::INFILTRATOR)
            score*=0.9
          else
            score*=1.3
          end
        else
          score *= 0.8
        end
        if opponent.status==PBStatuses::SLEEP && !(!opponent.abilitynulled && opponent.ability == PBAbilities::EARLYBIRD) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::SHEDSKIN)
          score*=1.2
        end
        if @doublebattle
          score *= 0.5
        end
        #if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) ^ @trickroom!=0
        #  score*=0.9
        #end
        if opponent.effects[PBEffects::HyperBeam]>0
          score*=1.5
        end
        if score<=startscore
          score*=0.3
        end
      when 0x116 # Sucker Punch
        knowncount = 0
        alldam = true
        if aimem.length > 0
          for j in aimem
            knowncount+=1
            if j.basedamage<=0
              alldam = false
            end
          end
        end
        if knowncount==4 && alldam
          score*=1.3
        else
          score*=0.6 if checkAIhealing(aimem)
          score*=0.8 if checkAImoves(PBStuff::SETUPMOVE,aimem)
          if attacker.lastMoveUsed==26 # Sucker Punch last turn
            check = rand(3)
            if check != 1
              score*=0.3
            end
            if checkAImoves(PBStuff::SETUPMOVE,aimem)
              score*=0.5
            end
          end
          if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=0.8
            if initialscores.length>0
              test = initialscores[scoreindex]
              if initialscores.max!=test
                score*=0.6
              end
            end
          else
            if checkAIpriority(aimem)
              score*=0.5
            else
              score*=1.3
            end
          end
        end
      when 0x117 # Follow Me
        if @doublebattle && attacker.pbPartner.hp!=0
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            score*=1.2
          end
          
          if (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::MOODY)
            score*=1.3
          end
          if attacker.pbPartner.turncount<1
            score*=1.2
          else
            score*=0.8
          end
          if attacker.hp==attacker.totalhp
            score*=1.2
          else
            score*=0.8
            if attacker.hp*2 < attacker.totalhp
              score*=0.5
            end
          end
          if attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill) || attacker.pbSpeed<pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)
            score*=1.2
          end
        else
          score*=0
        end
      when 0x118 # Gravity
        maxdam=0
        maxid = -1
        if aimem.length > 0
          for j in aimem
            tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)
            if tempdam>maxdam
              maxdam=tempdam
              maxid = j.id
            end
          end
        end
        if @field.effects[PBEffects::Gravity]>0
          score*=0
        else
          for i in attacker.moves
            if i.accuracy<=70
              score*=2
              break
            end
          end
          if attacker.pbHasMove?((PBMoves::ZAPCANNON)) || attacker.pbHasMove?((PBMoves::INFERNO))
            score*=3
          end
          if maxid==(PBMoves::SKYDROP) || maxid==(PBMoves::BOUNCE) || maxid==(PBMoves::FLY) || maxid==(PBMoves::JUMPKICK) || maxid==(PBMoves::FLYINGPRESS) || maxid==(PBMoves::HIJUMPKICK) || maxid==(PBMoves::SPLASH)
            score*=2
          end
          for m in attacker.moves
            if m.id==(PBMoves::SKYDROP) || m.id==(PBMoves::BOUNCE) || m.id==(PBMoves::FLY) || m.id==(PBMoves::JUMPKICK) || m.id==(PBMoves::FLYINGPRESS) || m.id==(PBMoves::HIJUMPKICK) || m.id==(PBMoves::SPLASH)
              score*=0
              break
            end
          end
          if attacker.pbHasType?(:GROUND) && (opponent.pbHasType?(:FLYING) || (!opponent.abilitynulled && opponent.ability == PBAbilities::LEVITATE) || (oppitemworks && opponent.item == PBItems::AIRBALLOON))
            score*=2
          end
          if (attitemworks && attacker.item == PBItems::AMPLIFIELDROCK) || $fefieldeffect==37
            score*=1.5
          end
          psyvar=false
          poisonvar=false
          fairyvar=false
          darkvar=false
          for mon in pbParty(attacker.index)
            next if mon.nil?
            if mon.hasType?(:PSYCHIC)
              psyvar=true
            end
            if mon.hasType?(:POISON)
              poisonvar=true
            end
            if mon.hasType?(:FAIRY)
              fairyvar=true
            end
            if mon.hasType?(:DARK)
              darkvar=true
            end
          end
          if $fefieldeffect==11
            if !attacker.pbHasType?(:POISON)
              score*=3
            else
              score*=0.5
            end
            if !poisonvar
              score*=3
            end
          elsif $fefieldeffect==21
            if attacker.pbHasType?(:WATER)
              score*=2
            else
              score*=0.5
            end
          elsif $fefieldeffect==35
            if !attacker.pbHasType?(:FLYING) && !(!attacker.abilitynulled && attacker.ability == PBAbilities::LEVITATE)
              score*=2
            end
            if opponent.pbHasType?(:FLYING) || (!opponent.abilitynulled && opponent.ability == PBAbilities::LEVITATE)
              score*=2
            end
            if psyvar || fairyvar || darkvar
              score*=2
              if attacker.pbHasType?(:PSYCHIC) || attacker.pbHasType?(:FAIRY) || attacker.pbHasType?(:DARK)
                score*=2
              end
            end
          end
        end
      when 0x119 # Magnet Rise
        if !(attacker.effects[PBEffects::MagnetRise]>0 || attacker.effects[PBEffects::Ingrain] || attacker.effects[PBEffects::SmackDown])
          if checkAIbest(aimem,1,[PBTypes::GROUND],false,attacker,opponent,skill)# Highest expected dam from a ground move
            score*=3
          end
          if opponent.pbHasType?(:GROUND)
            score*=3
          end
          if $fefieldeffect==1 || $fefieldeffect==17 || $fefieldeffect==18
            score*=1.3
          end
        else
          score*=0
        end
      when 0x11A # Telekinesis
        if !(opponent.effects[PBEffects::Telekinesis]>0 || opponent.effects[PBEffects::Ingrain] || opponent.effects[PBEffects::SmackDown] || @field.effects[PBEffects::Gravity]>0 || (oppitemworks && opponent.item == PBItems::IRONBALL) || opponent.species==50 || opponent.species==51 || opponent.species==769 || opponent.species==770 || (opponent.species==94 && opponent.form==1))
          for i in attacker.moves
            if i.accuracy<=70
              score+=10
              break
            end
          end
          if attacker.pbHasMove?((PBMoves::ZAPCANNON)) || attacker.pbHasMove?((PBMoves::INFERNO))
            score*=2
          end
          if $fefieldeffect==37
            if !(!opponent.abilitynulled && opponent.ability == PBAbilities::CLEARBODY) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::WHITESMOKE)
              score+=15
              miniscore=100
              miniscore*=1.3 if checkAIhealing(aimem)
              if (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || (!attacker.abilitynulled && attacker.ability == PBAbilities::ARENATRAP) || opponent.effects[PBEffects::MeanLook]>=0 ||  opponent.pbNonActivePokemonCount==0
                miniscore*=1.4
              end
              if opponent.status==PBStatuses::BURN || opponent.status==PBStatuses::POISON
                miniscore*=1.2
              end
              ministat= 5*statchangecounter(opponent,1,7,-1)
              ministat+=100
              ministat/=100.0
              miniscore*=ministat
              if attacker.pbNonActivePokemonCount==0
                miniscore*=0.5
              end
              if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE) || (!opponent.abilitynulled && opponent.ability == PBAbilities::DEFIANT) || (!opponent.abilitynulled && opponent.ability == PBAbilities::COMPETITIVE) || (!opponent.abilitynulled && opponent.ability == PBAbilities::CONTRARY)
                miniscore*=0.1
              end
              if attacker.status!=0
                miniscore*=0.7
              end
              miniscore/=100.0
              score*=miniscore
            end
          end
        else
          score*=0
        end
      when 0x11B # Sky Uppercut
      when 0x11C # Smack Down
        if !(opponent.effects[PBEffects::Ingrain] || opponent.effects[PBEffects::SmackDown] || @field.effects[PBEffects::Gravity]>0 || (oppitemworks && opponent.item == PBItems::IRONBALL)) && opponent.effects[PBEffects::Substitute]<=0
          miniscore=100
          if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            if opponent.pbHasMove?((PBMoves::BOUNCE)) || opponent.pbHasMove?((PBMoves::FLY)) || opponent.pbHasMove?((PBMoves::SKYDROP))
              miniscore*=1.3
            else
              opponent.effects[PBEffects::TwoTurnAttack]!=0
              miniscore*=2
            end
          end
          groundmove = false
          for i in attacker.moves
            if i.type == 4
              groundmove = true
            end
          end
          if opponent.pbHasType?(:FLYING) || (!opponent.abilitynulled && opponent.ability == PBAbilities::LEVITATE)
            miniscore*=2
          end
          miniscore/=100.0
          score*=miniscore
        end
      when 0x11D # After You
      when 0x11E # Quash
      when 0x11F # Trick Room
        count = -1
        sweepvar = false
        for i in pbParty(attacker.index)
          count+=1
          next if i.nil?
          temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
          if temprole.include?(PBMonRoles::SWEEPER)
            sweepvar = true
          end
        end
        if !sweepvar
          score*=1.3
        end
        if roles.include?(PBMonRoles::TANK) || roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          score*=1.3
        end
        if roles.include?(PBMonRoles::LEAD)
          score*=1.5
        end
        if @doublebattle
          score*=1.3
        end
        if (attitemworks && attacker.item == PBItems::AMPLIFIELDROCK) || (attitemworks && attacker.item == PBItems::FOCUSSASH)
          score*=1.5
        end
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==5 || $fefieldeffect==35 || $fefieldeffect==37 # Chess/New World/Psychic Terrain
            score*=1.5
          end
        end
        if attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill) || (attitemworks && attacker.item == PBItems::IRONBALL)
          if @trickroom > 0
            score*=0
          else
            score*=2
            #experimental -- cancels out drop if killing moves
            if initialscores.length>0
              score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
            end
            #end experimental
          end
        else
          if @trickroom > 0
            score*=1.3
          else
            score*=0
          end
        end
      when 0x120 # Ally Switch
        if checkAIdamage(aimem,attacker,opponent,skill)<attacker.hp && attacker.pbNonActivePokemonCount!=0 && (aimem.length > 0)
          score*=1.3
          sweepvar = false
          for i in pbParty(attacker.index)
            next if i.nil?
            temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
            if temprole.include?(PBMonRoles::SWEEPER)
              sweepvar = true
            end
          end
          if sweepvar
            score*=2
          end
          if attacker.pbNonActivePokemonCount<3
            score*=2
          end
          if attacker.pbOwnSide.effects[PBEffects::StealthRock] || attacker.pbOwnSide.effects[PBEffects::Spikes]>0
            score*=0.5
          end
        else
          score*=0
        end
      when 0x121 # Foul Play
      when 0x122 # Secret Sword
      when 0x123 # Synchonoise
        if !opponent.pbHasType?(attacker.type1) && !opponent.pbHasType?(attacker.type2)
          score*=0
        end
      when 0x124 # Wonder Room
        if @field.effects[PBEffects::WonderRoom]!=0
          score*=0
        else
          if (attitemworks && attacker.item == PBItems::AMPLIFIELDROCK) || $fefieldeffect==35 || $fefieldeffect==37
            score*=1.3
          end
          if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
            if attacker.defense>attacker.spdef
              score*=0.5
            else
              score*=2
            end
          else
            if attacker.defense<attacker.spdef
              score*=0.5
            else
              score*=2
            end
          end
          if attacker.attack>attacker.spatk
            if pbRoughStat(opponent,PBStats::DEFENSE,skill)>pbRoughStat(opponent,PBStats::SPDEF,skill)
              score*=2
            else
              score*=0.5
            end
          else
            if pbRoughStat(opponent,PBStats::DEFENSE,skill)<pbRoughStat(opponent,PBStats::SPDEF,skill)
              score*=2
            else
              score*=0.5
            end
          end
        end
      when 0x125 # Last Resort
        totalMoves = []
        for i in attacker.moves
          totalMoves[i.id] = false
          if i.function == 0x125
            totalMoves[i.id] = true
          end
          if i.id == 0
            totalMoves[i.id] = true
          end
        end
        for i in attacker.movesUsed
          for j in attacker.moves
            if i == j.id
              totalMoves[j.id] = true
            end
          end
        end
        for i in attacker.moves
          if !totalMoves[i.id]
            score=0
          end
        end
      when 0x126 # Shadow Stuff
        score*=1.2 # Shadow moves are more preferable
      when 0x127 # Shadow Stuff
        score*=1.2 # Shadow moves are more preferable
        if opponent.pbCanParalyze?(false)
          score*=1.3
          if skill>=PBTrainerAI.mediumSkill
            aspeed=pbRoughStat(attacker,PBStats::SPEED,skill)
            ospeed=pbRoughStat(opponent,PBStats::SPEED,skill)
            if aspeed<ospeed
              score*=1.3
            elsif aspeed>ospeed
              score*=0.6
            end
          end
          if skill>=PBTrainerAI.highSkill
            score*=0.6 if (!opponent.abilitynulled && opponent.ability == PBAbilities::GUTS)
            score*=0.6 if (!opponent.abilitynulled && opponent.ability == PBAbilities::MARVELSCALE)
            score*=0.6 if (!opponent.abilitynulled && opponent.ability == PBAbilities::QUICKFEET)
          end
        end
      when 0x128 # Shadow Stuff
        score*=1.2 # Shadow moves are more preferable
        if opponent.pbCanBurn?(false)
          score*=1.3
          if skill>=PBTrainerAI.highSkill
            score*=0.6 if (!opponent.abilitynulled && opponent.ability == PBAbilities::GUTS)
            score*=0.6 if (!opponent.abilitynulled && opponent.ability == PBAbilities::MARVELSCALE)
            score*=0.6 if (!opponent.abilitynulled && opponent.ability == PBAbilities::QUICKFEET)
            score*=0.6 if (!opponent.abilitynulled && opponent.ability == PBAbilities::FLAREBOOST)
          end
        end
      when 0x129 # Shadow Stuff
        score*=1.2 # Shadow moves are more preferable
        if opponent.pbCanFreeze?(false)
          score*=1.3
          if skill>=PBTrainerAI.highSkill
            score*=0.8 if (!opponent.abilitynulled && opponent.ability == PBAbilities::MARVELSCALE)
          end
        end
      when 0x12A # Shadow Stuff
        score*=1.2 # Shadow moves are more preferable
        if opponent.pbCanConfuse?(false)
          score*=1.3
        else
          if skill>=PBTrainerAI.mediumSkill
            score*=0.1
          end
        end
      when 0x12B # Shadow Stuff
        score*=1.2 # Shadow moves are more preferable
        if !opponent.pbCanReduceStatStage?(PBStats::DEFENSE)
          score*=0.1
        else
          score*=1.4 if attacker.turncount==0
          score+=opponent.stages[PBStats::DEFENSE]*20
        end
      when 0x12C # Shadow Stuff
        score*=1.2 # Shadow moves are more preferable
        if !opponent.pbCanReduceStatStage?(PBStats::EVASION)
          score*=0.1
        else
          score+=opponent.stages[PBStats::EVASION]*15
        end
      when 0x12D # Shadow Stuff
        score*=1.2 # Shadow moves are more preferable
      when 0x12E # Shadow Stuff
        score*=1.2 # Shadow moves are more preferable
        score*=1.2 if opponent.hp>=(opponent.totalhp/2.0)
        score*=0.8 if attacker.hp<(attacker.hp/2.0)
      when 0x12F # Shadow Stuff
        score*=1.2 # Shadow moves are more preferable
        score*=0 if opponent.effects[PBEffects::MeanLook]>=0
      when 0x130 # Shadow Stuff
        score*=1.2 # Shadow moves are more preferable
        score*=0.6
      when 0x131 # Shadow Stuff
        score*=1.2 # Shadow moves are more preferable
        if pbCheckGlobalAbility(:AIRLOCK) ||
          pbCheckGlobalAbility(:CLOUDNINE)
          score*=0.1
        elsif pbWeather==PBWeather::SHADOWSKY
          score*=0.1
        end
      when 0x132 # Shadow Stuff
        score*=1.2 # Shadow moves are more preferable
        if opponent.pbOwnSide.effects[PBEffects::Reflect]>0 ||
          opponent.pbOwnSide.effects[PBEffects::LightScreen]>0 ||
          opponent.pbOwnSide.effects[PBEffects::Safeguard]>0
          score*=1.3
          score*=0.1 if attacker.pbOwnSide.effects[PBEffects::Reflect]>0 ||
                      attacker.pbOwnSide.effects[PBEffects::LightScreen]>0 ||
                      attacker.pbOwnSide.effects[PBEffects::Safeguard]>0
        else
          score*=0
        end
      when 0x133 # Kings Shield
        if opponent.turncount==0
          score*=1.5
        end
        score*=0.6 if opponent.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SPEEDBOOST) && attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          score*=4
          #experimental -- cancels out drop if killing moves
          if initialscores.length>0
            score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
          end
          #end experimental
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON)) || attacker.effects[PBEffects::Ingrain] || attacker.effects[PBEffects::AquaRing] || $fefieldeffect==2
          score*=1.2
        end
        if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN
          score*=1.2
          if opponent.effects[PBEffects::Toxic]>0
            score*=1.3
          end
        end
        if attacker.status==PBStatuses::POISON || attacker.status==PBStatuses::BURN
          score*=0.8
          if attacker.effects[PBEffects::Toxic]>0
            score*=0.3
          end
        end
        if opponent.effects[PBEffects::LeechSeed]>=0
          score*=1.3
        end
        if opponent.effects[PBEffects::PerishSong]!=0
          score*=2
        end
        if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
          score*=0.3
        end
        if opponent.vanished
          score*=2
          if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.5
          end
        end
        if ((attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && (attacker.species == PBSpecies::AEGISLASH) && attacker.form==1
          score*=4
          #experimental -- cancels out drop if killing moves
          if initialscores.length>0
            score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
          end
          #end experimental
        else
          score*=0.8
        end
        score*=0.3 if checkAImoves(PBStuff::PROTECTIGNORINGMOVE,aimem)
        if attacker.effects[PBEffects::Wish]>0
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=3
          else
            score*=1.4
          end
        end
        if aimem.length > 0
          contactcheck=false
          for j in aimem
            contactcheck=j.isContactMove?
          end
          if contactcheck
            score*=1.3
          end
        end
        if skill>=PBTrainerAI.bestSkill && $fefieldeffect==31 # Fairy Tale
          score*=1.4
        else
          if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
            score*=1.5
          end
          if attacker.status==0
            score*=0.1 if checkAImoves([PBMoves::WILLOWISP,PBMoves::THUNDERWAVE,PBMoves::TOXIC],aimem)
          end
        end
        ratesharers=[
        391,   # Protect
        121,   # Detect
        122,   # Quick Guard
        515,   # Wide Guard
        361,   # Endure
        584,   # King's Shield
        603,    # Spiky Shield
        641    # Baneful Bunker
          ]
        if ratesharers.include?(attacker.lastMoveUsed)
          score/=(attacker.effects[PBEffects::ProtectRate]*2.0)
        end
      when 0x134 # Electric Terrain
        sleepvar=false
        if aimem.length > 0
          for j in aimem
            sleepvar = true if j.function==0x03
          end
        end
        if @field.effects[PBEffects::Terrain]==0 && $fefieldeffect!=1 &&
          $fefieldeffect!=22 && $fefieldeffect!=35
          miniscore = getFieldDisruptScore(attacker,opponent,skill)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::SURGESURFER)
            miniscore*=1.5
          end
          if attacker.pbHasType?(:ELECTRIC)
            miniscore*=1.5
          end
          elecvar=false
          for mon in pbParty(attacker.index)
            next if mon.nil?
            if mon.hasType?(:ELECTRIC)
              elecvar=true
            end
          end
          if elecvar
            miniscore*=2
          end
          if opponent.pbHasType?(:ELECTRIC)
            miniscore*=0.5
          end
          for m in attacker.moves
            if m.function==0x03
              miniscore*=0.5
              break
            end
          end
          if sleepvar
            miniscore*=2
          end
          if (attitemworks && attacker.item == PBItems::AMPLIFIELDROCK)
            miniscore*=2
          end
          score*=miniscore
        else
          score*=0
        end
      when 0x135 # Grassy Terrain
        firevar=false
        grassvar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:FIRE)
            firevar=true
          end
          if mon.hasType?(:GRASS)
            grassvar=true
          end
        end
        if @field.effects[PBEffects::Terrain]==0 && $fefieldeffect!=2 &&
          $fefieldeffect!=22 && $fefieldeffect!=35
          miniscore = getFieldDisruptScore(attacker,opponent,skill)
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            miniscore*=1.5
          end
          if attacker.pbHasType?(:FIRE)
            miniscore*=2
          end
          if firevar
            miniscore*=2
          end
          if opponent.pbHasType?(:FIRE)
            miniscore*=0.5
            if pbWeather!=PBWeather::RAINDANCE
              miniscore*=0.5
            end
            if attacker.pbHasType?(:GRASS)
              miniscore*=0.5
            end
          else
            if attacker.pbHasType?(:GRASS)
              miniscore*=2
            end
          end
          if grassvar
            miniscore*=2
          end
          miniscore*=0.5 if checkAIhealing(aimem)
          miniscore*=0.5 if checkAImoves([PBMoves::SLUDGEWAVE],aimem)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::GRASSPELT)
            miniscore*=1.5
          end
          if (attitemworks && attacker.item == PBItems::AMPLIFIELDROCK)
            miniscore*=2
          end
          score*=miniscore
        else
          score*=0
        end
      when 0x136 # Misty Terrain
        fairyvar=false
        dragonvar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:FAIRY)
            fairyvar=true
          end
          if mon.hasType?(:DRAGON)
            dragonvar=true
          end
        end
        if @field.effects[PBEffects::Terrain]==0 && $fefieldeffect!=3 &&
          $fefieldeffect!=22 && $fefieldeffect!=35
          miniscore = getFieldDisruptScore(attacker,opponent,skill)
          if fairyvar
            miniscore*=2
          end
          if !attacker.pbHasType?(:FAIRY) && opponent.pbHasType?(:DRAGON)
            miniscore*=2
          end
          if attacker.pbHasType?(:DRAGON)
            miniscore*=0.5
          end
          if opponent.pbHasType?(:FAIRY)
            miniscore*=0.5
          end
          if attacker.pbHasType?(:FAIRY) && opponent.spatk>opponent.attack
            miniscore*=2
          end
          if (attitemworks && attacker.item == PBItems::AMPLIFIELDROCK)
            miniscore*=2
          end
          score*=miniscore
        else
          score*=0
        end
      when 0x137 # Flying Press
        if opponent.effects[PBEffects::Minimize]
          score*=2
        end
        if @field.effects[PBEffects::Gravity]>0
          score*=0
        end
      when 0x138 # Noble Roar
        if (!opponent.pbCanReduceStatStage?(PBStats::ATTACK) && !opponent.pbCanReduceStatStage?(PBStats::SPATK)) || (opponent.stages[PBStats::ATTACK]==-6 && opponent.stages[PBStats::SPATK]==-6) || (opponent.stages[PBStats::ATTACK]>0 && opponent.stages[PBStats::SPATK]>0)
          score*=0
        else
          miniscore=100
          ministat= 5*statchangecounter(opponent,1,7,-1)
          ministat+=100
          ministat/=100.0
          miniscore*=ministat
          if $fefieldeffect==31 || $fefieldeffect==32
            miniscore*=2
          end
          miniscore*= unsetupminiscore(attacker,opponent,skill,move,roles,1,false)
          miniscore/=100.0
          score*=miniscore
        end
      when 0x139 # Draining Kiss
        minimini = score*0.01
        miniscore = (opponent.hp*minimini)*(3.0/4.0)
        if miniscore > (attacker.totalhp-attacker.hp)
          miniscore = (attacker.totalhp-attacker.hp)
        end
        if attacker.totalhp>0
          miniscore/=(attacker.totalhp).to_f
        end
        if (attitemworks && attacker.item == PBItems::BIGROOT)
          miniscore*=1.3
        end
        miniscore+=1
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::LIQUIDOOZE)
          miniscore = (2-miniscore)
        end
        if (attacker.hp!=attacker.totalhp || ((attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0))) && opponent.effects[PBEffects::Substitute]==0
          score*=miniscore
        end
        if $fefieldeffect==31 && move.id==(PBMoves::DRAININGKISS)
          if opponent.status==PBStatuses::SLEEP
            score*=0.2
          end
        end
      when 0x13A # Aromatic Mist
        newopp = attacker.pbOppositeOpposing
        movecheck = false
        if skill>=PBTrainerAI.bestSkill
          if @aiMoveMemory[2][newopp.pokemonIndex].length>0
            for j in @aiMoveMemory[2][newopp.pokemonIndex]
              movecheck=true if (PBStuff::PHASEMOVE).include?(j.id)
            end
          end
        elsif skill>=PBTrainerAI.mediumSkill
          movecheck=checkAImoves(PBStuff::PHASEMOVE,aimem)
        end
        if @doublebattle && opponent==attacker.pbPartner && opponent.stages[PBStats::SPDEF]!=6
          if newopp.spatk > newopp.attack
            score*=2
          else
            score*=0.5
          end
          if initialscores.length>0
            score*=1.3 if hasbadmoves(initialscores,scoreindex,20)
          end
          if opponent.hp*(1.0/opponent.totalhp)>0.75
            score*=1.1
          end
          if opponent.effects[PBEffects::Yawn]>0 || opponent.effects[PBEffects::LeechSeed]>=0 || opponent..effects[PBEffects::Attract]>=0 || opponent.status!=0
            score*=0.3
          end
          if movecheck
            score*=0.2
          end
          if !opponent.abilitynulled && opponent.ability == PBAbilities::SIMPLE
            score*=2
          end
          if !newopp.abilitynulled && newopp.ability == PBAbilities::UNAWARE
            score*=0.5
          end
          if (oppitemworks && opponent.item == PBItems::LEFTOVERS) || ((oppitemworks && opponent.item == PBItems::BLACKSLUDGE) && opponent.pbHasType?(:POISON))
            score*=1.2
          end
          if !opponent.abilitynulled && opponent.ability == PBAbilities::CONTRARY
            score*=0
          end
          if $fefieldeffect==3
            score*=2
          end
        else
          score*=0
        end
      when 0x13B # Eerie Impulse
        if (pbRoughStat(opponent,PBStats::SPATK,skill)<pbRoughStat(opponent,PBStats::ATTACK,skill)) || opponent.stages[PBStats::SPATK]>1 || !opponent.pbCanReduceStatStage?(PBStats::SPATK)
          if move.basedamage==0
            score=0
          end
        else
          miniscore=100
          if opponent.stages[PBStats::SPATK]<0
            minimini = 5*opponent.stages[PBStats::SPATK]
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          miniscore*= unsetupminiscore(attacker,opponent,skill,move,roles,1,false)
          miniscore/=100.0
          score*=miniscore
        end
      when 0x13C # Belch
        if attacker.effects[PBEffects::Belch]==false
          score*=0
        end
      when 0x13D # Parting Shot
        if (!opponent.pbCanReduceStatStage?(PBStats::ATTACK) && !opponent.pbCanReduceStatStage?(PBStats::SPATK)) || (opponent.stages[PBStats::ATTACK]==-6 && opponent.stages[PBStats::SPATK]==-6) || (opponent.stages[PBStats::ATTACK]>0 && opponent.stages[PBStats::SPATK]>0)
          score*=0
        else
          if attacker.pbNonActivePokemonCount==0
            if attacker.pbOwnSide.effects[PBEffects::StealthRock]
              score*=0.7
            end
            if attacker.pbOwnSide.effects[PBEffects::StickyWeb]
              score*=0.6
            end
            if attacker.pbOwnSide.effects[PBEffects::Spikes]>0
              score*=0.9**attacker.pbOwnSide.effects[PBEffects::Spikes]
            end
            if attacker.pbOwnSide.effects[PBEffects::ToxicSpikes]>0
              score*=0.9**attacker.pbOwnSide.effects[PBEffects::ToxicSpikes]
            end
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=1.1
            end
            sweepvar = false
            for i in pbParty(attacker.index)
              next if i.nil?
              temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
              if temprole.include?(PBMonRoles::SWEEPER)
                sweepvar = true
              end
            end
            if sweepvar
              score*=1.5
            end
            if roles.include?(PBMonRoles::LEAD)
              score*=1.1
            end
            if roles.include?(PBMonRoles::PIVOT)
              score*=1.2
            end
            ministat= 5*statchangecounter(opponent,1,7,-1)
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
            miniscore= (-5)*statchangecounter(attacker,1,7,1)
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
            if attacker.effects[PBEffects::Toxic]>0 || attacker.effects[PBEffects::Attract]>-1 || attacker.effects[PBEffects::Confusion]>0
              score*=1.3
            end
            if attacker.effects[PBEffects::LeechSeed]>-1
              score*=1.5
            end
            miniscore=130
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || (!attacker.abilitynulled && attacker.ability == PBAbilities::ARENATRAP) || opponent.effects[PBEffects::MeanLook]>=0 ||  opponent.pbNonActivePokemonCount==0
              miniscore*=1.4
            end
            ministat= 5*statchangecounter(opponent,1,7,-1)
            ministat+=100
            ministat/=100.0
            miniscore*=ministat
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE) || (!opponent.abilitynulled && opponent.ability == PBAbilities::DEFIANT) || (!opponent.abilitynulled && opponent.ability == PBAbilities::COMPETITIVE) || (!opponent.abilitynulled && opponent.ability == PBAbilities::CONTRARY)
              miniscore*=0.1
            end
            miniscore/=100.0
            score*=miniscore
          end
        end
      when 0x13E # Geomancy
        maxdam = checkAIdamage(aimem,attacker,opponent,skill)
        if !(attitemworks && attacker.item == PBItems::POWERHERB)
          if maxdam>attacker.hp
            score*=0.4
          elsif attacker.hp*(1.0/attacker.totalhp)<0.5
            score*=0.6
          end
          if attacker.turncount<2
            score*=1.5
          else
            score*=0.7
          end
          if opponent.effects[PBEffects::TwoTurnAttack]!=0 || opponent.effects[PBEffects::HyperBeam]>0
            score*=2
          end
          if @doublebattle
            score*=0.5
          end
        else
          score*=2
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::UNBURDEN)
            score*=1.5
          end
        end
        miniscore=100
        if attacker.effects[PBEffects::Substitute]>0 || attacker.effects[PBEffects::Disguise]
          miniscore*=1.3
        end
        if initialscores.length>0
          miniscore*=1.3 if hasbadmoves(initialscores,scoreindex,40)
        end
        if (attacker.hp.to_f)/attacker.totalhp>0.75
          miniscore*=1.2
        end
        if opponent.effects[PBEffects::Yawn]>0
          miniscore*=1.7
        end
        if maxdam*4<attacker.hp
          miniscore*=1.2
        else
          if move.basedamage==0
            miniscore*=0.8
            if maxdam>attacker.hp
              miniscore*=0.1
            end
          end
        end
        if opponent.status!=0
          miniscore*=1.2
        end
        if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
          miniscore*=1.3
        end
        if opponent.effects[PBEffects::Encore]>0
          if opponent.moves[(opponent.effects[PBEffects::EncoreIndex])].basedamage==0
            miniscore*=1.5
          end
        end
        if attacker.effects[PBEffects::Confusion]>0
          miniscore*=0.5
        end
        if attacker.effects[PBEffects::LeechSeed]>=0 || attacker.effects[PBEffects::Attract]>=0
          miniscore*=0.3
        end
        miniscore*=0.5 if checkAImoves(PBStuff::SWITCHOUTMOVE,aimem)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SIMPLE)
          miniscore*=2
        end
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
          miniscore*=0.5
        end
        miniscore/=100.0
        score*=miniscore
        miniscore=100
        if attacker.stages[PBStats::SPEED]<0
          ministat=attacker.stages[PBStats::SPEED]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        ministat=0
        ministat+=opponent.stages[PBStats::ATTACK]
        ministat+=opponent.stages[PBStats::SPATK]
        ministat+=opponent.stages[PBStats::SPEED]
        if ministat>0
          minimini=(-5)*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        miniscore*=1.3 if checkAIhealing(aimem)
        if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          miniscore*=1.5
        end
        if roles.include?(PBMonRoles::SWEEPER)
          miniscore*=1.3
        end
        if attacker.status==PBStatuses::PARALYSIS
          miniscore*=0.5
        end
        miniscore*=0.6 if checkAIpriority(aimem)
        miniscore/=100.0
        if !attacker.pbTooHigh?(PBStats::SPATK)
          score*=miniscore
        end
        miniscore=100
        if attacker.effects[PBEffects::Toxic]>0
          miniscore*=0.2
        end
        if pbRoughStat(opponent,PBStats::ATTACK,skill)<pbRoughStat(opponent,PBStats::SPATK,skill)
          miniscore*=1.3
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          miniscore*=1.3
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
          miniscore*=1.2
        end
        healmove=false
        for j in attacker.moves
          if j.isHealingMove?
            healmove=true
          end
        end
        if healmove
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::LEECHSEED))
          miniscore*=1.3
        end
        if attacker.pbHasMove?((PBMoves::PAINSPLIT))
          miniscore*=1.2
        end
        miniscore/=100.0
        if !attacker.pbTooHigh?(PBStats::SPDEF)
          score*=miniscore
        end
        miniscore=100
        if attacker.stages[PBStats::SPATK]<0
          ministat=attacker.stages[PBStats::SPATK]
          minimini=5*ministat
          minimini+=100
          minimini/=100.0
          miniscore*=minimini
        end
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          miniscore*=0.8
        end
        if @trickroom!=0
          miniscore*=0.2
        else
          miniscore*=0.2 if checkAImoves([PBMoves::TRICKROOM],aimem)
        end
        miniscore/=100.0
        if !attacker.pbTooHigh?(PBStats::SPEED)
          score*=miniscore=0
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score*=0
        end
        psyvar=false
        fairyvar=false
        darkvar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:PSYCHIC)
            psyvar=true
          end
          if mon.hasType?(:FAIRY)
            fairyvar=true
          end
          if mon.hasType?(:DARK)
            darkvar=true
          end
        end
        if $fefieldeffect==35
          if !(!attacker.abilitynulled && attacker.ability == PBAbilities::LEVITATE) && !attacker.pbHasType?(:FLYING)
            score*=2
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::LEVITATE) || opponent.pbHasType?(:FLYING)
            score*=2
          end
          if psyvar || fairyvar || darkvar
            score*=2
            if attacker.pbHasType?(:PSYCHIC) || attacker.pbHasType?(:FAIRY) || attacker.pbHasType?(:DARK)
              score*=2
            end
          end
        end
        if attacker.pbTooHigh?(PBStats::SPATK) && attacker.pbTooHigh?(PBStats::SPDEF) && attacker.pbTooHigh?(PBStats::SPEED)
          score*=0
        end
      when 0x13F # Venom Drench
        if opponent.status==PBStatuses::POISON || $fefieldeffect==10 || $fefieldeffect==11 || $fefieldeffect==19 || $fefieldeffect==26
          if (!opponent.pbCanReduceStatStage?(PBStats::ATTACK) && !opponent.pbCanReduceStatStage?(PBStats::SPATK)) || (opponent.stages[PBStats::ATTACK]==-6 && opponent.stages[PBStats::SPATK]==-6) || (opponent.stages[PBStats::ATTACK]>0 && opponent.stages[PBStats::SPATK]>0)
            score*=0.5
          else
            miniscore=100
            if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
              miniscore*=1.4
            end
            sweepvar = false
            for i in pbParty(attacker.index)
              next if i.nil?
              temprole = pbGetMonRole(i,opponent,skill,count,pbParty(attacker.index))
              if temprole.include?(PBMonRoles::SWEEPER)
                sweepvar = true
              end
            end
            if sweepvar
              miniscore*=1.1
            end
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || (!attacker.abilitynulled && attacker.ability == PBAbilities::ARENATRAP) || opponent.effects[PBEffects::MeanLook]>=0 ||  opponent.pbNonActivePokemonCount==0
              miniscore*=1.5
            end
            ministat= 5*statchangecounter(opponent,1,7,-1)
            ministat+=100
            ministat/=100.0
            miniscore*=ministat
            if attacker.pbHasMove?((PBMoves::FOULPLAY))
              miniscore*=0.5
            end
            miniscore/=100.0
            score*=miniscore
          end
          if (pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) || opponent.stages[PBStats::SPEED]>0 || !opponent.pbCanReduceStatStage?(PBStats::SPEED)
            score*=0.5
          else
            miniscore=100
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
              miniscore*=0.9
            end
            if attacker.pbHasMove?((PBMoves::ELECTROBALL))
              miniscore*=1.5
            end
            if attacker.pbHasMove?((PBMoves::GYROBALL))
              miniscore*=0.5
            end
            if (oppitemworks && opponent.item == PBItems::LAGGINGTAIL) || (oppitemworks && opponent.item == PBItems::IRONBALL)
              miniscore*=0.8
            end
            miniscore*=0.1 if checkAImoves([PBMoves::TRICKROOM],aimem) || @trickroom!=0
            miniscore*=1.3 if checkAImoves([PBMoves::ELECTROBALL],aimem)
            miniscore*=0.5 if checkAImoves([PBMoves::GYROBALL],aimem)
            miniscore/=100.0
            score*=miniscore
            if attacker.pbNonActivePokemonCount==0
              score*=0.5
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE) || (!opponent.abilitynulled && opponent.ability == PBAbilities::CONTRARY) || (!opponent.abilitynulled && opponent.ability == PBAbilities::DEFIANT)
              score*=0
            end
          end
        else
          score*=0
        end
      when 0x140 # Spiky Shield
        if opponent.turncount==0
          score*=1.5
        end
        score*=0.3 if opponent.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SPEEDBOOST) && attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          score*=4
          #experimental -- cancels out drop if killing moves
          if initialscores.length>0
            score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
          end
          #end experimental
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON)) || attacker.effects[PBEffects::Ingrain] || attacker.effects[PBEffects::AquaRing] || $fefieldeffect==2
          score*=1.2
        end
        if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN
          score*=1.2
          if opponent.effects[PBEffects::Toxic]>0
            score*=1.3
          end
        end
        if attacker.status==PBStatuses::POISON || attacker.status==PBStatuses::BURN
          score*=0.7
          if attacker.effects[PBEffects::Toxic]>0
            score*=0.3
          end
        end
        if opponent.effects[PBEffects::LeechSeed]>=0
          score*=1.3
        end
        if opponent.effects[PBEffects::PerishSong]!=0
          score*=2
        end
        if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
          score*=0.3
        end
        if opponent.vanished
          score*=2
          if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.5
          end
        end
        score*=0.1 if checkAImoves(PBStuff::PROTECTIGNORINGMOVE,aimem)
        if attacker.effects[PBEffects::Wish]>0
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=3
          else
            score*=1.4
          end
        end
        if aimem.length > 0
          contactcheck=false
          maxdam=0
          for j in aimem
            contactcheck=j.isContactMove?
          end
          if contactcheck
            score*=1.3
          end
        end
        if attacker.status==0
          score*=0.7 if checkAImoves([PBMoves::WILLOWISP,PBMoves::THUNDERWAVE,PBMoves::TOXIC],aimem)
        end
        ratesharers=[
        391,   # Protect
        121,   # Detect
        122,   # Quick Guard
        515,   # Wide Guard
        361,   # Endure
        584,   # King's Shield
        603,    # Spiky Shield
        641    # Baneful Bunker
          ]
        if ratesharers.include?(attacker.lastMoveUsed)
          score/=(attacker.effects[PBEffects::ProtectRate]*2.0)
        end
      when 0x141 # Sticky Web
        if !attacker.pbOpposingSide.effects[PBEffects::StickyWeb]
          if roles.include?(PBMonRoles::LEAD)
            score*=1.3
          end
          if (attitemworks && attacker.item == PBItems::FOCUSSASH) && attacker.hp==attacker.totalhp
            score*=1.3
          end
          if attacker.turncount<2
            score*=1.3
          end
          if opponent.pbNonActivePokemonCount>1
            miniscore = opponent.pbNonActivePokemonCount
            miniscore/=100.0
            miniscore*=0.3
            miniscore+=1
            score*=miniscore
          else
            score*=0.2
          end
          if skill>=PBTrainerAI.bestSkill
            for k in 0...pbParty(opponent.index).length
              next if pbParty(opponent.index)[k].nil?
              if @aiMoveMemory[2][k].length>0
                movecheck=false
                for j in @aiMoveMemory[2][k]
                  movecheck=true if j.id==(PBMoves::DEFOG) || j.id==(PBMoves::RAPIDSPIN)
                end
                score*=0.3 if movecheck
              end
            end
          elsif skill>=PBTrainerAI.mediumSkill
            score*=0.3 if checkAImoves([PBMoves::DEFOG,PBMoves::RAPIDSPIN],aimem)
          end
          if $fefieldeffect==15
            score*=2
          end
        else
          score*=0
        end
        if $fefieldeffect==19
          if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) || opponent.stages[PBStats::SPEED]>0 || !opponent.pbCanReduceStatStage?(PBStats::SPEED)
            score*=0
          else
            score+=15
            miniscore=100
            if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
              miniscore*=1.1
            end
            if opponent.pbNonActivePokemonCount==0 || (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || opponent.effects[PBEffects::MeanLook]>0
              miniscore*=1.3
            end
            if opponent.stages[PBStats::SPEED]<0
              minimini = 5*opponent.stages[PBStats::SPEED]
              minimini+=100
              minimini/=100.0
              miniscore*=minimini
            end
            if attacker.pbNonActivePokemonCount==0
              miniscore*=0.5
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE) || (!opponent.abilitynulled && opponent.ability == PBAbilities::COMPETITIVE) || (!opponent.abilitynulled && opponent.ability == PBAbilities::DEFIANT) || (!opponent.abilitynulled && opponent.ability == PBAbilities::CONTRARY)
              miniscore*=0.1
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
              miniscore*=0.5
            end
            if attacker.pbHasMove?((PBMoves::ELECTROBALL))
              miniscore*=1.5
            end
            if attacker.pbHasMove?((PBMoves::GYROBALL))
              miniscore*=0.5
            end
            if (oppitemworks && opponent.item == PBItems::LAGGINGTAIL) || (oppitemworks && opponent.item == PBItems::IRONBALL)
              miniscore*=0.1
            end
            miniscore*=0.1 if checkAImoves([PBMoves::TRICKROOM],aimem) || @trickroom!=0
            miniscore*=1.3 if checkAImoves([PBMoves::ELECTROBALL],aimem)
            miniscore*=0.5 if checkAImoves([PBMoves::GYROBALL],aimem)
            miniscore/=100.0
            score*=miniscore
          end
        end
      when 0x142 # Topsy-Turvy
        ministat= 10* statchangecounter(opponent,1,7)
        ministat+=100
        if ministat<0
          ministat=0
        end
        ministat/=100.0
        if opponent == attacker.pbPartner
          ministat = 2-ministat
        end
        score*=ministat
        if $fefieldeffect!=22 && $fefieldeffect!=35 && $fefieldeffect!=36
          effcheck = PBTypes.getCombinedEffectiveness(opponent.type1,attacker.type1,attacker.type2)
          if effcheck>4
            score*=2
          else
            if effcheck!=0 && effcheck<4
              score*=0.5
            end
            if effcheck==0
              score*=0.1
            end
          end
          effcheck = PBTypes.getCombinedEffectiveness(opponent.type2,attacker.type1,attacker.type2)
          if effcheck>4
            score*=2
          else
            if effcheck!=0 && effcheck<4
              score*=0.5
            end
            if effcheck==0
              score*=0.1
            end
          end
          effcheck = PBTypes.getCombinedEffectiveness(attacker.type1,opponent.type1,opponent.type2)
          if effcheck>4
            score*=0.5
          else
            if effcheck!=0 && effcheck<4
              score*=2
            end
            if effcheck==0
              score*=3
            end
          end
          effcheck = PBTypes.getCombinedEffectiveness(attacker.type2,opponent.type1,opponent.type2)
          if effcheck>4
            score*=0.5
          else
            if effcheck!=0 && effcheck<4
              score*=2
            end
            if effcheck==0
              score*=3
            end
          end
        end
      when 0x143 # Forest's Curse
        grassvar = false
        if aimem.length > 0
          for j in aimem
            grassvar = true if (j.type == PBTypes::GRASS)
          end
        end
        effmove = false
        for m in attacker.moves
          if (m.type == PBTypes::FIRE) || (m.type == PBTypes::ICE) || (m.type == PBTypes::BUG) || (m.type == PBTypes::FLYING) || (m.type == PBTypes::POISON)
            effmove = true
            break
          end
        end
        if effmove
          score*=1.5
        else
          score*=0.7
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          if attacker.pbHasMove?((PBMoves::TOXIC)) && (opponent.pbHasType?(:STEEL) || opponent.pbHasType?(:POISON))
            score*=1.5
          end
        end
        if grassvar
          score*=0.5
        else
          score*=1.1
        end
        if (opponent.ability == PBAbilities::MULTITYPE) || (opponent.ability == PBAbilities::RKSSYSTEM) || (opponent.type1==(PBTypes::GRASS) && opponent.type2==(PBTypes::GRASS)) || (!opponent.abilitynulled && opponent.ability == PBAbilities::PROTEAN) || (!opponent.abilitynulled && opponent.ability == PBAbilities::COLORCHANGE)
          score*=0
        end
        if $fefieldeffect == 15 || $fefieldeffect == 31
          if !opponent.effects[PBEffects::Curse]
            score+=25
            ministat= 5*statchangecounter(opponent,1,7)
            ministat+=100
            ministat/=100.0
            score*=ministat
            if opponent.pbNonActivePokemonCount==0 || (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || opponent.effects[PBEffects::MeanLook]>0
              score*=1.3
            else
              score*=0.8
            end
            if @doublebattle
              score*=0.5
            end
            if initialscores.length>0
              score*=1.3 if hasbadmoves(initialscores,scoreindex,25)
            end
          end
        end
      when 0x144 # Trick or Treat
        ghostvar = false
        if aimem.length > 0
          for j in aimem
            ghostvar = true if (j.type == PBTypes::GHOST)
          end
        end
        effmove = false
        for m in attacker.moves
          if (m.type == PBTypes::DARK) || (m.type == PBTypes::GHOST)
            effmove = true
            break
          end
        end
        if effmove
          score*=1.5
        else
          score*=0.7
        end
        if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
          if attacker.pbHasMove?((PBMoves::TOXIC)) && (opponent.pbHasType?(:STEEL) || opponent.pbHasType?(:POISON))
            score*=1.5
          end
        end
        if ghostvar
          score*=0.5
        else
          score*=1.1
        end
        if (opponent.ability == PBAbilities::MULTITYPE) || (opponent.ability == PBAbilities::RKSSYSTEM) || (opponent.type1==(PBTypes::GHOST) && opponent.type2==(PBTypes::GHOST)) || (!opponent.abilitynulled && opponent.ability == PBAbilities::PROTEAN) || (!opponent.abilitynulled && opponent.ability == PBAbilities::COLORCHANGE)
          score*=0
        end
      when 0x145 # Fairy Lock
        if attacker.effects[PBEffects::PerishSong]==1 || attacker.effects[PBEffects::PerishSong]==2
          score*=0
        else
          if opponent.effects[PBEffects::PerishSong]==2
            score*=10
          end
          if opponent.effects[PBEffects::PerishSong]==1
            score*=20
          end
          if attacker.effects[PBEffects::LeechSeed]>=0
            score*=0.8
          end
          if opponent.effects[PBEffects::LeechSeed]>=0
            score*=1.2
          end
          if opponent.effects[PBEffects::Curse]
            score*=1.3
          end
          if attacker.effects[PBEffects::Curse]
            score*=0.7
          end
          if opponent.effects[PBEffects::Confusion]>0
            score*=1.1
          end
          if attacker.effects[PBEffects::Confusion]>0
            score*=1.1
          end
        end
      when 0x146 # Magnetic Flux
        if !((!attacker.abilitynulled && attacker.ability == PBAbilities::PLUS) || (!attacker.abilitynulled && attacker.ability == PBAbilities::MINUS) || (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::PLUS) || (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::MINUS))
          score*=0
        else
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::PLUS) || (!attacker.abilitynulled && attacker.ability == PBAbilities::MINUS)
            miniscore = setupminiscore(attacker,opponent,skill,move,false,10,true,initialscores,scoreindex)
            score*=miniscore
            miniscore=100
            if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
              miniscore*=1.5
            end
            if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
              miniscore*=1.2
            end
            healmove=false
            for j in attacker.moves
              if j.isHealingMove?
                healmove=true
              end
            end
            if healmove
              miniscore*=1.7
            end
            if attacker.pbHasMove?((PBMoves::LEECHSEED))
              miniscore*=1.3
            end
            if attacker.pbHasMove?((PBMoves::PAINSPLIT))
              miniscore*=1.2
            end
            if attacker.stages[PBStats::SPDEF]!=6 && attacker.stages[PBStats::DEFENSE]!=6
              score*=miniscore
            end
          elsif @doublebattle && attacker.pbPartner.stages[PBStats::SPDEF]!=6 && attacker.pbPartner.stages[PBStats::DEFENSE]!=6
            score*=0.7
            if initialscores.length>0
              score*=1.3 if hasbadmoves(initialscores,scoreindex,20)
            end
            if attacker.pbPartner.hp >= attacker.pbPartner.totalhp*0.75
              score*=1.1
            end
            if attacker.pbPartner.effects[PBEffects::Yawn]>0 || attacker.pbPartner.effects[PBEffects::LeechSeed]>=0 || attacker.pbPartner.effects[PBEffects::Attract]>=0 || attacker.pbPartner.status!=0
              score*=0.3
            end
            if movecheck
              score*=0.3
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
              score*=0.5
            end
            if attacker.pbPartner.hasWorkingItem(:LEFTOVERS) || (attacker.pbPartner.hasWorkingItem(:BLACKSLUDGE) && attacker.pbPartner.pbHasType?(:POISON))
              score*=1.2
            end
          else
            score*=0
          end
        end
      when 0x147 # Fell Stinger
        if attacker.stages[PBStats::ATTACK]!=6
          if score>=100
            score*=2
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=2
            end
          end
        end
      when 0x148 # Ion Deluge
        maxnormal = checkAIbest(aimem,1,[PBTypes::NORMAL],false,attacker,opponent,skill)
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=0.9
        elsif (!attacker.abilitynulled && attacker.ability == PBAbilities::MOTORDRIVE)
          if maxnormal
            score*=1.5
          end
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::LIGHTNINGROD) || (!attacker.abilitynulled && attacker.ability == PBAbilities::VOLTABSORB)
          if ((attacker.hp.to_f)/attacker.totalhp)<0.6
            if maxnormal
              score*=1.5
            end
          end
        end
        if attacker.pbHasType?(:GROUND)
          score*=1.1
        end
        if @doublebattle
          if (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::MOTORDRIVE) || (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::LIGHTNINGROD) || (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::VOLTABSORB)
            score*=1.2
          end
          if attacker.pbPartner.pbHasType?(:GROUND)
            score*=1.1
          end
        end
        if !maxnormal
          score*=0.5
        end
        if $fefieldeffect != 35 && $fefieldeffect != 1 && $fefieldeffect != 22
          miniscore = getFieldDisruptScore(attacker,opponent,skill)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::SURGESURFER)
            miniscore*=1.5
          end
          if attacker.pbHasType?(:ELECTRIC)
            miniscore*=1.5
          end
          elecvar=false
          for mon in pbParty(attacker.index)
            next if mon.nil?
            if mon.hasType?(:ELECTRIC)
              elecvar=true
            end
          end
          if elecvar
            miniscore*=1.5
          end
          if opponent.pbHasType?(:ELECTRIC)
            miniscore*=0.5
          end
          for m in attacker.moves
            if m.function==0x03
              miniscore*=0.5
              break
            end
          end
          if sleepcheck
            miniscore*=2
          end
          if (attitemworks && attacker.item == PBItems::AMPLIFIELDROCK)
            miniscore*=2
          end
          score*=miniscore
        end
      when 0x149 # Crafty Shield
        if attacker.lastMoveUsed==565
          score*=0.5
        else
          nodam = true
          for m in opponent.moves
            if m.basedamage>0
              nodam=false
              break
            end
          end
          if nodam
            score+=10
          end
          if attacker.hp==attacker.totalhp
            score*=1.5
          end
        end
        if $fefieldeffect==31
          score+=25
          miniscore=100
          if attacker.effects[PBEffects::Substitute]>0 || attacker.effects[PBEffects::Disguise]
            miniscore*=1.3
          end
          if initialscores.length>0
            miniscore*=1.3 if hasbadmoves(initialscores,scoreindex,20)
          end
          if (attacker.hp.to_f)/attacker.totalhp>0.75
            miniscore*=1.1
          end
          if opponent.effects[PBEffects::HyperBeam]>0
            miniscore*=1.2
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=1.3
          end
          miniscore*=1.1 if checkAIdamage(aimem,attacker,opponent,skill) < attacker.hp*0.3 && (aimem.length > 0)
          if attacker.turncount<2
            miniscore*=1.1
          end
          if opponent.status!=0
            miniscore*=1.1
          end
          if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
            miniscore*=1.3
          end
          if opponent.effects[PBEffects::Encore]>0
            if opponent.moves[(opponent.effects[PBEffects::EncoreIndex])].basedamage==0
              miniscore*=1.5
            end
          end
          if attacker.effects[PBEffects::Confusion]>0
            miniscore*=0.5
          end
          if attacker.effects[PBEffects::LeechSeed]>=0 || attacker.effects[PBEffects::Attract]>=0
            miniscore*=0.3
          end
          if attacker.effects[PBEffects::Toxic]>0
            miniscore*=0.2
          end
          miniscore*=0.2 if checkAImoves(PBStuff::SWITCHOUTMOVE,aimem)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::SIMPLE)
            miniscore*=2
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
            miniscore*=0.5
          end
          if @doublebattle
            miniscore*=0.3
          end
          miniscore*=0.3 if checkAIdamage(aimem,attacker,opponent,skill)<attacker.hp*0.12 && (aimem.length > 0)
          miniscore/=100.0
          score*=miniscore
          miniscore=100
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            miniscore*=1.5
          end
          if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
            miniscore*=1.2
          end
          healmove=false
          for j in attacker.moves
            if j.isHealingMove?
              healmove=true
            end
          end
          if healmove
            miniscore*=1.7
          end
          if attacker.pbHasMove?((PBMoves::LEECHSEED))
            miniscore*=1.3
          end
          if attacker.pbHasMove?((PBMoves::PAINSPLIT))
            miniscore*=1.2
          end
          if attacker.stages[PBStats::SPDEF]!=6 && attacker.stages[PBStats::DEFENSE]!=6
            score*=miniscore
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            score=0
          end
        end
      when 0x14A # Doesn't exist
      when 0x14B # Doesn't exist
      when 0x14C # Doesn't exist
      when 0x14D # Doesn't exist
      when 0x14E # Doesn't exist
      when 0x14F # Doesn't exist
      when 0x150 # Flower Shield
        opp1 = attacker.pbOppositeOpposing
        opp2 = opp1.pbPartner
        if @doublebattle && opponent.pbHasType?(:GRASS) && opponent==attacker.pbPartner && opponent.stages[PBStats::DEFENSE]!=6
          if $fefieldeffect!=33 || $fecounter==0
            if opp1.attack>opp1.spatk
              score*=2
            else
              score*=0.5
            end
            if opp2.attack>opp2.spatk
              score*=2
            else
              score*=0.5
            end
          else
            score*=2
          end
          if initialscores.length>0
            score*=1.3 if hasbadmoves(initialscores,scoreindex,20)
          end
          if (opponent.hp.to_f)/opponent.totalhp>0.75
            score*=1.1
          end
          if opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::Attract]>=0 || opponent.status!=0 || opponent.effects[PBEffects::Yawn]>0
            score*=0.3
          end
          if movecheck
            score*=0.2
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SIMPLE)
            score*=2
          end
          if (!opp1.abilitynulled && opp1.ability == PBAbilities::UNAWARE)
            score*=0.5
          end
          if $fefieldeffect==33 && $fecounter!=4
            score+=30
          end
          if ($fefieldeffect==33 && $fecounter>0) || $fefieldeffect==31
            score+=20
            miniscore=100
            if attacker.effects[PBEffects::Substitute]>0 || attacker.effects[PBEffects::Disguise]
              miniscore*=1.3
            end
            if initialscores.length>0
              miniscore*=1.3 if hasbadmoves(initialscores,scoreindex,20)
            end
            if (opponent.hp.to_f)/opponent.totalhp>0.75
              miniscore*=1.1
            end
            if opp1.effects[PBEffects::HyperBeam]>0
              miniscore*=1.2
            end
            if opp1.effects[PBEffects::Yawn]>0
              miniscore*=1.3
            end
            miniscore*=1.1 if checkAIdamage(aimem,attacker,opponent,skill) < opponent.hp*0.3 && (aimem.length > 0)
            if opponent.turncount<2
              miniscore*=1.1
            end
            if opp1.status!=0
              miniscore*=1.1
            end
            if opp1.status==PBStatuses::SLEEP || opp1.status==PBStatuses::FROZEN
              miniscore*=1.3
            end
            if opp1.effects[PBEffects::Encore]>0
              if opp1.moves[(opp1.effects[PBEffects::EncoreIndex])].basedamage==0
                miniscore*=1.5
              end
            end
            if opponent.effects[PBEffects::Confusion]>0
              miniscore*=0.5
            end
            if opponent.effects[PBEffects::LeechSeed]>=0 || attacker.effects[PBEffects::Attract]>=0
              miniscore*=0.3
            end
            if opponent.effects[PBEffects::Toxic]>0
              miniscore*=0.2
            end
            miniscore*=0.2 if checkAImoves(PBStuff::SWITCHOUTMOVE,aimem)
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::SIMPLE)
              miniscore*=2
            end
            if (!opp1.abilitynulled && opp1.ability == PBAbilities::UNAWARE)
              miniscore*=0.5
            end
            if @doublebattle
              miniscore*=0.3
            end
            miniscore*=0.3 if checkAIdamage(aimem,attacker,opponent,skill)<opponent.hp*0.12 && (aimem.length > 0)
            miniscore/=100.0
            score*=miniscore
            miniscore=100
            if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
              miniscore*=1.5
            end
            if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON))
              miniscore*=1.2
            end
            healmove=false
            for j in attacker.moves
              if j.isHealingMove?
                healmove=true
              end
            end
            if healmove
              miniscore*=1.7
            end
            if attacker.pbHasMove?((PBMoves::LEECHSEED))
              miniscore*=1.3
            end
            if attacker.pbHasMove?((PBMoves::PAINSPLIT))
              miniscore*=1.2
            end
            if attacker.stages[PBStats::SPDEF]!=6 && attacker.stages[PBStats::DEFENSE]!=6
              score*=miniscore
            end
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
              score=0
            end
          end
        else
          score*=0
        end
      when 0x151 # Rototiller
        opp1 = attacker.pbOppositeOpposing
        opp2 = opp1.pbPartner
        if @doublebattle && opponent.pbHasType?(:GRASS) && opponent==attacker.pbPartner && opponent.stages[PBStats::SPATK]!=6 && opponent.stages[PBStats::ATTACK]!=6
          if initialscores.length>0
            score*=1.3 if hasbadmoves(initialscores,scoreindex,20)
          end
          if (opponent.hp.to_f)/opponent.totalhp>0.75
            score*=1.1
          end
          if opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::Attract]>=0 || opponent.status!=0 || opponent.effects[PBEffects::Yawn]>0
            score*=0.3
          end
          if movecheck
            score*=0.2
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SIMPLE)
            score*=2
          end
          if (!opp1.abilitynulled && opp1.ability == PBAbilities::UNAWARE)
            score*=0.5
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::CONTRARY)
            score*=0
          end
          if $fefieldeffect==33 && $fecounter!=4
            score+=30
          end
          if $fefieldeffect==33
            score+=20
            miniscore=100
            if attacker.effects[PBEffects::Substitute]>0 || attacker.effects[PBEffects::Disguise]
              miniscore*=1.3
            end
            if initialscores.length>0
              miniscore*=1.3 if hasbadmoves(initialscores,scoreindex,20)
            end
            if (opponent.hp.to_f)/opponent.totalhp>0.75
              miniscore*=1.1
            end
            if opp1.effects[PBEffects::HyperBeam]>0
              miniscore*=1.2
            end
            if opp1.effects[PBEffects::Yawn]>0
              miniscore*=1.3
            end
            miniscore*=1.1 if checkAIdamage(aimem,attacker,opponent,skill) < opponent.hp*0.25 && (aimem.length > 0)
            if opponent.turncount<2
              miniscore*=1.1
            end
            if opp1.status!=0
              miniscore*=1.1
            end
            if opp1.status==PBStatuses::SLEEP || opp1.status==PBStatuses::FROZEN
              miniscore*=1.3
            end
            if opp1.effects[PBEffects::Encore]>0
              if opp1.moves[(opp1.effects[PBEffects::EncoreIndex])].basedamage==0
                miniscore*=1.5
              end
            end
            if opponent.effects[PBEffects::Confusion]>0
              miniscore*=0.2
            end
            if opponent.effects[PBEffects::LeechSeed]>=0 || attacker.effects[PBEffects::Attract]>=0
              miniscore*=0.6
            end
            miniscore*=0.5 if checkAImoves(PBStuff::SWITCHOUTMOVE,aimem)
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::SIMPLE)
              miniscore*=2
            end
            if (!opp1.abilitynulled && opp1.ability == PBAbilities::UNAWARE)
              miniscore*=0.5
            end
            if @doublebattle
              miniscore*=0.3
            end
            ministat=0
            ministat+=opponent.stages[PBStats::SPEED] if opponent.stages[PBStats::SPEED]<0
            ministat*=5
            ministat+=100
            ministat/=100.0
            miniscore*=ministat
            ministat=0
            ministat+=opponent.stages[PBStats::ATTACK]
            ministat+=opponent.stages[PBStats::SPEED]
            ministat+=opponent.stages[PBStats::SPATK]
            if ministat > 0
              ministat*=(-5)
              ministat+=100
              ministat/=100.0
              miniscore*=ministat
            end
            miniscore/=100.0
            score*=miniscore
            miniscore=100
            miniscore*=1.3 if checkAIhealing(aimem)
            if attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
              miniscore*=1.5
            end
            if roles.include?(PBMonRoles::SWEEPER)
              miniscore*=1.3
            end
            if attacker.status==PBStatuses::PARALYSIS
              miniscore*=0.5
            end
            miniscore*=0.3 if checkAImoves([PBMoves::FOULPLAY],aimem)
            if attacker.hp==attacker.totalhp && (attitemworks && attacker.item == PBItems::FOCUSSASH)
              miniscore*=1.4
            end
            miniscore*=0.4 if checkAIpriority(aimem)
            if attacker.stages[PBStats::SPATK]!=6 && attacker.stages[PBStats::ATTACK]!=6
              score*=miniscore
            end
          end
        else
          score*=0
        end
      when 0x152 # Powder
        firecheck = false
        movecount = 0
        if aimem.length > 0
          for j in aimem
            movecount+=1
            if j.type == (PBTypes::FIRE)
              firecheck = true
            end
          end
        end
        if !(opponent.pbHasType?(:GRASS) || (!opponent.abilitynulled && opponent.ability == PBAbilities::OVERCOAT) || (oppitemworks && opponent.item == PBItems::SAFETYGOGGLES))
          if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.2
          end
          if checkAIbest(aimem,1,[PBTypes::FIRE],false,attacker,opponent,skill)
            score*=3
          else
            if opponent.pbHasType?(:FIRE)
              score*=2
            else
              score*=0.2
            end
          end
          effcheck = PBTypes.getCombinedEffectiveness((PBTypes::FIRE),attacker.type1,attacker.type2)
          if effcheck>4
            score*=2
            if effcheck>8
              score*=2
            end
          end
          if attacker.lastMoveUsed==600
            score*=0.6
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::MAGICGUARD)
            score*=0.5
          end
          if !firecheck && movecount==4
            score*=0
          end
        else
          score*=0
        end
      when 0x153 # Electrify
        startscore = score
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::VOLTABSORB)
            if attacker.hp<attacker.totalhp*0.8
              score*=1.5
            else
              score*=0.1
            end
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::LIGHTNINGROD)
            if attacker.spatk > attacker.attack && attacker.stages[PBStats::SPATK]!=6
              score*=1.5
            else
              score*=0.1
            end
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::MOTORDRIVE)
            if attacker.stages[PBStats::SPEED]!=6
              score*=1.2
            else
              score*=0.1
            end
          end
          if attacker.pbHasType?(:GROUND)
            score*=1.3
          end
          if score==startscore
            score*=0.1
          end
          score*=0.5 if checkAIpriority(aimem)
        else
          score*=0
        end
      when 0x154 # Mat Block
        if attacker.turncount==0
          if @doublebattle
            score*=1.3
            if ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && ((attacker.pbSpeed>pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0))
              score*=1.2
            else
              score*=0.7
              if ((attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && ((attacker.pbSpeed<pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0))
                score*=0
              end
            end
            score*=0.3 if checkAImoves(PBStuff::SETUPMOVE,aimem) && checkAIhealing(aimem)
            if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON)) || attacker.effects[PBEffects::Ingrain] || attacker.effects[PBEffects::AquaRing] || $fefieldeffect==2
              score*=1.2
            end
            if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN
              score*=1.2
              if opponent.effects[PBEffects::Toxic]>0
                score*=1.3
              end
            end
            if attacker.status==PBStatuses::POISON || attacker.status==PBStatuses::BURN
              score*=0.7
              if attacker.effects[PBEffects::Toxic]>0
                score*=0.3
              end
            end
            if opponent.effects[PBEffects::LeechSeed]>=0
              score*=1.3
            end
            if opponent.effects[PBEffects::PerishSong]!=0
              score*=2
            end
            if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
              score*=0.3
            end
            if opponent.vanished
              score*=2
              if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
                score*=1.5
              end
            end
            score*=0.1 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
            if attacker.effects[PBEffects::Wish]>0
              score*=1.3
            end
          end
        else
          score*=0
        end
      when 0x155 # Thousand Waves
        if !(opponent.effects[PBEffects::MeanLook]>=0 || opponent.effects[PBEffects::Ingrain] || opponent.pbHasType?(:GHOST)) && opponent.effects[PBEffects::Substitute]<=0
          score*=0.1 if checkAImoves(PBStuff::PIVOTMOVE,aimem)
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::RUNAWAY)
            score*=0.1
          end
          if attacker.pbHasMove?((PBMoves::PERISHSONG))
            score*=1.5
          end
          if opponent.effects[PBEffects::PerishSong]>0
            score*=4
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::ARENATRAP) || (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG)
            score*=0
          end
          if opponent.effects[PBEffects::Attract]>=0
            score*=1.3
          end
          if opponent.effects[PBEffects::LeechSeed]>=0
            score*=1.3
          end
          if opponent.effects[PBEffects::Curse]
            score*=1.5
          end
          miniscore*=0.7 if attacker.moves.any? {|moveloop| (PBStuff::SWITCHOUTMOVE).include?(moveloop)}
          ministat=(-5)*statchangecounter(opponent,1,7)
          ministat+=100
          ministat/=100.0
          score*=ministat
          if opponent.effects[PBEffects::Confusion]>0
            score*=1.1
          end
        end
      when 0x156 # NOT USED
      when 0x157 # Hyperspace Hole
        if checkAImoves(PBStuff::PROTECTMOVE,aimem)
          score*=1.1
          ratesharers=[
          391,   # Protect
          121,   # Detect
          122,   # Quick Guard
          515,   # Wide Guard
          361,   # Endure
          584,   # King's Shield
          603,    # Spiky Shield
          641    # Baneful Bunker
            ]
          if !ratesharers.include?(opponent.lastMoveUsed)
            score*=1.2
          end
        end
        if !(!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD)
          if attacker.stages[PBStats::ACCURACY]<0
            miniscore = (-5)*attacker.stages[PBStats::ACCURACY]
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
          if opponent.stages[PBStats::EVASION]>0
            miniscore = (5)*opponent.stages[PBStats::EVASION]
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
          end
          if (oppitemworks && opponent.item == PBItems::LAXINCENSE) || (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER)
            score*=1.2
          end
          if ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) || ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL)
            score*=1.3
          end
          if opponent.vanished && ((attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0))
            score*=3
          end
        end
      when 0x158 # Not Used
      when 0x159 # Hyperspace Fury
        startscore = score
        if attacker.species==720 && attacker.form==1 # Hoopa-U
          if checkAImoves(PBStuff::PROTECTMOVE,aimem)
            score*=1.1
            ratesharers=[
            391,   # Protect
            121,   # Detect
            122,   # Quick Guard
            515,   # Wide Guard
            361,   # Endure
            584,   # King's Shield
            603,    # Spiky Shield
            641    # Baneful Bunker
              ]
            if !ratesharers.include?(opponent.lastMoveUsed)
              score*=1.2
            end
          end
          if !(!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD)
            if attacker.stages[PBStats::ACCURACY]<0
              miniscore = (-5)*attacker.stages[PBStats::ACCURACY]
              miniscore+=100
              miniscore/=100.0
              score*=miniscore
            end
            if opponent.stages[PBStats::EVASION]>0
              miniscore = (5)*opponent.stages[PBStats::EVASION]
              miniscore+=100
              miniscore/=100.0
              score*=miniscore
            end
            if (oppitemworks && opponent.item == PBItems::LAXINCENSE) || (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER)
              score*=1.2
            end
            if ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) || ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL)
              score*=1.3
            end
            if opponent.vanished && (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=3
            end
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
            score*=1.7
          else
            if startscore<100
              score*=0.8
              if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
                score*=1.2
              else
                score*=0.8
              end
              score*=0.7 if checkAIhealing(aimem)
              if initialscores.length>0
                score*=0.5 if hasgreatmoves(initialscores,scoreindex,skill)
              end
              miniscore=100
              if opponent.pbNonActivePokemonCount!=0
                miniscore*=opponent.pbNonActivePokemonCount
                miniscore/=1000.0
                miniscore= 1-miniscore
                score*=miniscore
              end
              if opponent.pbNonActivePokemonCount!=0 && attacker.pbNonActivePokemonCount==0
                score*=0.7
              end
            end
          end
        else
          score*=0
        end
      when 0x15A # Future Sight Dummy
      when 0x15B # Aurora Veil
        if attacker.pbOwnSide.effects[PBEffects::AuroraVeil]<=0
          if pbWeather==PBWeather::HAIL || (skill>=PBTrainerAI.bestSkill && ($fefieldeffect==28 || $fefieldeffect==30 || $fefieldeffect==34 || $fefieldeffect==4 || $fefieldeffect==9 || $fefieldeffect==13 || $fefieldeffect==25))
            score*=1.5
            if attacker.pbOwnSide.effects[PBEffects::AuroraVeil]>0
              score*=0.1
            end
            if (attitemworks && attacker.item == PBItems::LIGHTCLAY)
              score*=1.5
            end
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=1.1
              score*=2 if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp && (checkAIdamage(aimem,attacker,opponent,skill)/2.0)<attacker.hp
            end
            if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
              score*=1.3
            end
            score*=0.1 if checkAImoves([PBMoves::DEFOG,PBMoves::RAPIDSPIN],aimem)
            if skill>=PBTrainerAI.bestSkill
              if $fefieldeffect==30 # Mirror
                score*=1.5
              end
            end
          else
            score=0
          end
        else
          score=0
        end
      when 0x15C # Baneful Bunker
        if opponent.turncount==0
          score*=1.5
        end
        score*=0.3 if opponent.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SPEEDBOOST) && attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill) && @trickroom==0
          score*=4
          #experimental -- cancels out drop if killing moves
          if initialscores.length>0
            score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
          end
          #end experimental
        end
        if (attitemworks && attacker.item == PBItems::LEFTOVERS) || ((attitemworks && attacker.item == PBItems::BLACKSLUDGE) && attacker.pbHasType?(:POISON)) || attacker.effects[PBEffects::Ingrain] || attacker.effects[PBEffects::AquaRing] || $fefieldeffect==2
          score*=1.2
        end
        if opponent.status!=0
          score*=0.8
        else
          if opponent.pbCanPoison?(false)
            score*=1.3
            if (!attacker.abilitynulled && attacker.ability == PBAbilities::MERCILESS)
              score*=1.3
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::POISONHEAL)
              score*=0.3
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::TOXICBOOST)
              score*=0.7
            end
          end
        end
        if attacker.status==PBStatuses::POISON || attacker.status==PBStatuses::BURN
          score*=0.7
          if attacker.effects[PBEffects::Toxic]>0
            score*=0.3
          end
        end
        if opponent.effects[PBEffects::LeechSeed]>=0
          score*=1.3
        end
        if opponent.effects[PBEffects::PerishSong]!=0
          score*=2
        end
        if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
          score*=0.3
        end
        if opponent.vanished
          score*=2
          if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.5
          end
        end
        score*=0.1 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
        if attacker.effects[PBEffects::Wish]>0
          if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
            score*=3
          else
            score*=1.4
          end
        end
        if aimem.length > 0
          contactcheck=false
          for j in aimem
            contactcheck=j.isContactMove?
          end
          if contactcheck
            score*=1.3
          end
        end
        ratesharers=[
        391,   # Protect
        121,   # Detect
        122,   # Quick Guard
        515,   # Wide Guard
        361,   # Endure
        584,   # King's Shield
        603,    # Spiky Shield
        641    # Baneful Bunker
          ]
        if ratesharers.include?(attacker.lastMoveUsed)
          score/=(attacker.effects[PBEffects::ProtectRate]*2.0)
        end
      when 0x15D # Beak Blast
        contactcheck = false
        if aimem.length > 0
          for j in aimem
            if j.isContactMove?
              contactcheck=true
            end
          end
        end
        if opponent.pbCanBurn?(false)
          miniscore=120
          ministat = 5*opponent.stages[PBStats::ATTACK]
          if ministat>0
            ministat+=100
            ministat/=100.0
            miniscore*=ministat
          end
          if !opponent.abilitynulled
            miniscore*=0.3 if opponent.ability == PBAbilities::NATURALCURE
            miniscore*=0.7 if opponent.ability == PBAbilities::MARVELSCALE
            miniscore*=0.1 if opponent.ability == PBAbilities::GUTS || opponent.ability == PBAbilities::FLAREBOOST
            miniscore*=0.7 if opponent.ability == PBAbilities::SHEDSKIN
            miniscore*=0.5 if opponent.ability == PBAbilities::SYNCHRONIZE && attacker.status==0
            miniscore*=0.5 if opponent.ability == PBAbilities::MAGICGUARD
            miniscore*=0.3 if opponent.ability == PBAbilities::QUICKFEET
            miniscore*=1.1 if opponent.ability == PBAbilities::STURDY
          end
          miniscore*=0.1 if checkAImoves([PBMoves::REST],aimem)
          miniscore*=0.2 if checkAImoves([PBMoves::FACADE],aimem)
          if opponent.attack > opponent.spatk
            miniscore*=1.7
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          if startscore==110
            miniscore*=0.8
          end
          miniscore-=100
          minimini = 100
          if contactcheck
            minimini*=1.5
          else
            if opponent.attack>opponent.spatk
              minimini*=1.3
            else
              minimini*=0.3
            end
          end
          minimini/=100.0
          miniscore*=minimini
          miniscore+=100
          miniscore/=100.0
          score*=miniscore
        end
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=0.7
        end
      when 0x15E # Burn Up
        maxdam=0
        maxtype = -1
        healvar=false
        if aimem.length > 0
          for j in aimem
            healvar=true if j.isHealingMove?
            tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)
            if tempdam>maxdam
              maxdam=tempdam
              maxtype = j.type
            end
          end
        end
        if !attacker.pbHasType?(:FIRE)
          score*=0
        else
          if score<100
            score*=0.9
            if healvar
              score*=0.5
            end
          end
          if initialscores.length>0
            score*=0.5 if hasgreatmoves(initialscores,scoreindex,skill)
          end
          miniscore=100
          if opponent.pbNonActivePokemonCount!=0
            miniscore*=opponent.pbNonActivePokemonCount
            miniscore/=100.0
            miniscore*=0.05
            miniscore = 1-miniscore
            score*=miniscore
          end
          if attacker.pbNonActivePokemonCount==0 && opponent.pbNonActivePokemonCount!=0
            score*=0.7
          end
          effcheck = PBTypes.getCombinedEffectiveness(opponent.type1,(PBTypes::FIRE),(PBTypes::FIRE))
          if effcheck > 4
            score*=1.5
          else
            if effcheck<4
              score*=0.5
            end
          end
          effcheck = PBTypes.getCombinedEffectiveness(opponent.type2,(PBTypes::FIRE),(PBTypes::FIRE))
          if effcheck > 4
            score*=1.5
          else
            if effcheck<4
              score*=0.5
            end
          end
          if maxtype!=-1
            effcheck = PBTypes.getCombinedEffectiveness(maxtype,(PBTypes::FIRE),(PBTypes::FIRE))
            if effcheck > 4
              score*=1.5
            else
              if effcheck<4
                score*=0.5
              end
            end
          end
        end
      when 0x15F # Clanging Scales
        maxdam=0
        maxphys = false
        healvar=false
        privar=false
        if aimem.length > 0
          for j in aimem
            healvar=true if j.isHealingMove?
            privar=true if j.priority>0
            tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)
            if tempdam>maxdam
              maxdam=tempdam
              maxphys = j.pbIsPhysical?(j.type)
            end
          end
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          score*=1.5
        else
          if score<100
            score*=0.8
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=1.3
            else
              score*=1.2 if checkAIpriority(aimem)
            end
            score*=0.5 if checkAIhealing(aimem)
          end
          if initialscores.length>0
            score*=0.5 if hasgreatmoves(initialscores,scoreindex,skill)
          end
          miniscore=100
          if opponent.pbNonActivePokemonCount!=0
            miniscore*=opponent.pbNonActivePokemonCount
            miniscore/=100.0
            miniscore*=0.05
            miniscore = 1-miniscore
            score*=miniscore
          end
          if attacker.pbNonActivePokemonCount==0 && opponent.pbNonActivePokemonCount!=0
            score*=0.7
          end
          if opponent.attack>opponent.spatk
            score*=0.7
          end
          score*=0.7 if checkAIbest(aimem,2,[],false,attacker,opponent,skill)
        end
      when 0x160 # Core Enforcer
        if !((PBStuff::FIXEDABILITIES).include?(opponent.ability))  && !opponent.effects[PBEffects::GastroAcid]
          miniscore = getAbilityDisruptScore(move,attacker,opponent,skill)
          if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            miniscore*=1.3
          else
            miniscore*=0.5
          end
          miniscore*=1.3 if checkAIpriority(aimem)
          score*=miniscore
        end
      when 0x161 # First Impression
        if attacker.turncount!=0
          score=0
        end
        if score==110
          score*=1.1
        end
      when 0x162 # Floral Healing
        if !@doublebattle || attacker.opposes?(opponent.index)
          score*=0
        else
          if !attacker.opposes?(opponent.index)
            if opponent.hp*(1.0/opponent.totalhp)<0.7 && opponent.hp*(1.0/opponent.totalhp)>0.3
              score*=3
            end
            if opponent.hp*(1.0/opponent.totalhp)<0.3
              score*=1.7
            end
            if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::Curse]
              score*=0.8
              if opponent.effects[PBEffects::Toxic]>0
                score*=0.7
              end
            end
            if opponent.hp*(1.0/opponent.totalhp)>0.8
              if ((attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && ((attacker.pbSpeed<pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0))
                score*=0.5
              else
                score*=0
              end
            end
          else
            score*=0
          end
        end
        if $fefieldeffect==2 || $fefieldeffect==31 || ($fefieldeffect==33 && $fecounter>1)
          score*=1.5
        end
        if attacker.status!=PBStatuses::POISON && ($fefieldeffect==10 || $fefieldeffect==11)
          score*=0.2
        end
      when 0x163 # Gear Up
        if !((!attacker.abilitynulled && attacker.ability == PBAbilities::PLUS) || (!attacker.abilitynulled && attacker.ability == PBAbilities::MINUS) || (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::PLUS) || (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::MINUS))
          score*=0
        else
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::PLUS) || (!attacker.abilitynulled && attacker.ability == PBAbilities::MINUS)
            miniscore = setupminiscore(attacker,opponent,skill,move,true,5,false,initialscores,scoreindex)
            if opponent.stages[PBStats::SPEED]<0
              ministat = 5*opponent.stages[PBStats::SPEED]
              ministat+=100
              ministat/=100.0
              miniscore*=ministat
            end
            ministat=0
            ministat+=opponent.stages[PBStats::ATTACK]
            ministat+=opponent.stages[PBStats::SPEED]
            ministat+=opponent.stages[PBStats::SPATK]
            if ministat>0
              ministat*=(-5)
              ministat+=100
              ministat/=100.0
              miniscore*=ministat
            end
            score*=miniscore
            miniscore=100
            miniscore*=1.3 if checkAIhealing(aimem)
            if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              miniscore*=1.5
            end
            if roles.include?(PBMonRoles::SWEEPER)
              miniscore*=1.3
            end
            if attacker.status==PBStatuses::BURN
              miniscore*=0.5
            end
            if attacker.status==PBStatuses::PARALYSIS
              miniscore*=0.5
            end
            miniscore*=0.3 if checkAImoves([PBMoves::FOULPLAY],aimem)
            if attacker.hp==attacker.totalhp && (((attitemworks && attacker.item == PBItems::FOCUSSASH) || ((!attacker.abilitynulled && attacker.ability == PBAbilities::STURDY) && !attacker.moldbroken)) && (pbWeather!=PBWeather::HAIL || attacker.pbHasType?(:ICE)) && (pbWeather!=PBWeather::SANDSTORM || attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND) || attacker.pbHasType?(:STEEL)))
              miniscore*=1.4
            end
            miniscore*=0.3 if checkAIpriority(aimem)
            physmove=false
            for j in attacker.moves
              if j.pbIsPhysical?(j.type)
                physmove=true
              end
            end
            specmove=false
            for j in attacker.moves
              if j.pbIsSpecial?(j.type)
                specmove=true
              end
            end
            if (!physmove || !attacker.pbTooHigh?(PBStats::ATTACK)) && (!specmove || !attacker.pbTooHigh?(PBStats::SPATK))
              miniscore/=100.0
              score*=miniscore
            end
          elsif @doublebattle && (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::PLUS) || (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::MINUS)
            if initialscores.length>0
              score*=1.3 if hasbadmoves(initialscores,scoreindex,20)
            end
            if attacker.pbPartner.hp>attacker.pbPartner.totalhp*0.75
              score*=1.1
            end
            if attacker.pbPartner.effects[PBEffects::Yawn]>0 || attacker.pbPartner.effects[PBEffects::LeechSeed]>=0 || attacker.pbPartner.effects[PBEffects::Attract]>=0 || attacker.pbPartner.status!=0
              score*=0.3
            end
            if movecheck
              score*=0.3
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
              score*=0.5
            end
          else
            score*=0
          end
        end
      when 0x164 # Instruct
        if !@doublebattle || opponent!=attacker.pbPartner || opponent.lastMoveUsedSketch<=0
          score=1
        else
          score*=3
          #if @opponent.trainertype==PBTrainers::MIME
          #  score+=35
          #end
          if attacker.pbPartner.hp*2 < attacker.pbPartner.totalhp
            score*=0.5
          else
            if attacker.pbPartner.hp==attacker.pbPartner.totalhp
              score*=1.2
            end
          end
          if initialscores.length>0
            badmoves=true
            for i in 0...initialscores.length
              next if attacker.moves[i].basedamage<=0
              next if i==scoreindex
              if initialscores[i]>20
                badmoves=false
              end
            end
            score*=1.2 if badmoves
          end
          if ((attacker.pbPartner.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && ((attacker.pbPartner.pbSpeed<pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0))
            score*=1.4
          end
          ministat = [attacker.pbPartner.attack,attacker.pbPartner.spatk].max
          minimini = [attacker.attack,attacker.spatk].max
          ministat-=minimini
          ministat+=100
          ministat/=100.0
          score*=ministat
          if attacker.pbPartner.hp==0
            score=1
          end
        end
      when 0x165 # Laser Focus
        if !(!opponent.abilitynulled && opponent.ability == PBAbilities::BATTLEARMOR) && !(!opponent.abilitynulled && opponent.ability == PBAbilities::SHELLARMOR) && attacker.effects[PBEffects::LaserFocus]==0
          miniscore = 100
          ministat=0
          ministat+=opponent.stages[PBStats::DEFENSE]
          ministat+=opponent.stages[PBStats::SPDEF]
          if ministat>0
            miniscore+= 10*ministat
          end
          ministat=0
          ministat+=attacker.stages[PBStats::ATTACK]
          ministat+=attacker.stages[PBStats::SPATK]
          if ministat>0
            miniscore+= 10*ministat
          end
          if attacker.effects[PBEffects::FocusEnergy]>0
            miniscore *= 0.8**attacker.effects[PBEffects::FocusEnergy]
          end
          miniscore/=100.0
          score*=miniscore
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::ANGERPOINT) && opponent.stages[PBStats::ATTACK] !=6
            score*=0.7
            if opponent.attack>opponent.spatk
              score*=0.2
            end
          end
        else
          score*=0
        end
      when 0x166 # Moongeist Beam
        damcount = 0
        firemove = false
        for m in attacker.moves
          if m.basedamage>0
            damcount+=1
            if m.type==(PBTypes::FIRE)
              firemove = true
            end
          end
        end
        if !opponent.moldbroken && !opponent.abilitynulled
          if opponent.ability == PBAbilities::SANDVEIL
            if pbWeather!=PBWeather::SANDSTORM
              score*=1.1
            end
          elsif opponent.ability == PBAbilities::VOLTABSORB || opponent.ability == PBAbilities::LIGHTNINGROD
            if move.type==(PBTypes::ELECTRIC)
              if damcount==1
                score*=3
              end
              if PBTypes.getCombinedEffectiveness((PBTypes::ELECTRIC),opponent.type1,opponent.type2)>4
                score*=2
              end
            end
          elsif opponent.ability == PBAbilities::WATERABSORB || opponent.ability == PBAbilities::STORMDRAIN || opponent.ability == PBAbilities::DRYSKIN
            if move.type==(PBTypes::WATER)
              if damcount==1
                score*=3
              end
              if PBTypes.getCombinedEffectiveness((PBTypes::WATER),opponent.type1,opponent.type2)>4
                score*=2
              end
            end
            if opponent.ability == PBAbilities::DRYSKIN && firemove
              score*=0.5
            end
          elsif opponent.ability == PBAbilities::FLASHFIRE
            if move.type==(PBTypes::FIRE)
              if damcount==1
                score*=3
              end
              if PBTypes.getCombinedEffectiveness((PBTypes::FIRE),opponent.type1,opponent.type2)>4
                score*=2
              end
            end
          elsif opponent.ability == PBAbilities::LEVITATE
            if move.type==(PBTypes::GROUND)
              if damcount==1
                score*=3
              end
              if PBTypes.getCombinedEffectiveness((PBTypes::GROUND),opponent.type1,opponent.type2)>4
                score*=2
              end
            end
          elsif opponent.ability == PBAbilities::WONDERGUARD
            score*=5
          elsif opponent.ability == PBAbilities::SOUNDPROOF
            if move.isSoundBased?
              score*=3
            end
          elsif opponent.ability == PBAbilities::THICKFAT
            if move.type==(PBTypes::FIRE) || move.type==(PBTypes::ICE)
              score*=1.5
            end
          elsif opponent.ability == PBAbilities::MOLDBREAKER
            score*=1.1
          elsif opponent.ability == PBAbilities::UNAWARE
            score*=1.7
          elsif opponent.ability == PBAbilities::MULTISCALE
            if attacker.hp==attacker.totalhp
              score*=1.5
            end
          elsif opponent.ability == PBAbilities::SAPSIPPER
            if move.type==(PBTypes::GRASS)
              if damcount==1
                score*=3
              end
              if PBTypes.getCombinedEffectiveness((PBTypes::GRASS),opponent.type1,opponent.type2)>4
                score*=2
              end
            end
          elsif opponent.ability == PBAbilities::SNOWCLOAK
            if pbWeather!=PBWeather::HAIL
              score*=1.1
            end
          elsif opponent.ability == PBAbilities::FURCOAT
            if attacker.attack>attacker.spatk
              score*=1.5
            end
          elsif opponent.ability == PBAbilities::FLUFFY
            score*=1.5
            if move.type==(PBTypes::FIRE)
              score*=0.5
            end
          elsif opponent.ability == PBAbilities::WATERBUBBLE
            score*=1.5
            if move.type==(PBTypes::FIRE)
              score*=1.3
            end
          end
        end
      when 0x167 # Pollen Puff
        if opponent==attacker.pbPartner
          score = 15
          if opponent.hp>opponent.totalhp*0.3 && opponent.hp<opponent.totalhp*0.7
            score*=3
          end
          if opponent.hp*(1.0/opponent.totalhp)<0.3
            score*=1.7
          end
          if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::Curse]
            score*=0.8
            if opponent.effects[PBEffects::Toxic]>0
              score*=0.7
            end
          end
          if opponent.hp*(1.0/opponent.totalhp)>0.8
            if ((attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)) && ((attacker.pbSpeed<pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0))
              score*=0.5
            else
              score*=0
            end
          end
          if attacker.effects[PBEffects::HealBlock]>0 || opponent.effects[PBEffects::HealBlock]>0
            score*=0
          end
        end
      when 0x168 # Psychic Terrain
        psyvar=false
        for mon in pbParty(attacker.index)
          next if mon.nil?
          if mon.hasType?(:PSYCHIC)
            psyvar=true
          end
        end
        pricheck = false
        for m in attacker.moves
          if m.priority>0
            pricheck=true
            break
          end
        end
        if @field.effects[PBEffects::Terrain]==0 && $fefieldeffect!=22
          $fefieldeffect!=35 && $fefieldeffect!=37
          miniscore = getFieldDisruptScore(attacker,opponent,skill)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::TELEPATHY)
            miniscore*=1.5
          end
          if attacker.pbHasType?(:PSYCHIC)
            miniscore*=1.5
          end
          if psyvar
            miniscore*=2
          end
          if opponent.pbHasType?(:PSYCHIC)
            miniscore*=0.5
          end
          if pricheck
            miniscore*=0.7
          end
          miniscore*=1.3 if checkAIpriority(aimem)
          if (attitemworks && attacker.item == PBItems::AMPLIFIELDROCK)
            miniscore*=2
          end
          score*=miniscore
        else
          score*=0
        end
      when 0x169 # Purify
        if opponent==attacker.pbPartner && opponent.status!=0
          score*=1.5
          if opponent.hp>opponent.totalhp*0.8
            score*=0.8
          else
            if opponent.hp>opponent.totalhp*0.3
              score*=2
            end
          end
          if opponent.effects[PBEffects::Toxic]>3
            score*=1.3
          end
          if opponent.pbHasMove?((PBMoves::HEX))
            score*=1.3
          end
        else
          score*=0
        end
      when 0x16A # Revelation Dance
      when 0x16B # Shell Trap
        maxdam=0
        specialvar = false
        if aimem.length > 0
        for j in aimem
            tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)
            if tempdam>maxdam
              maxdam=tempdam
              if j.pbIsSpecial?(j.type)
                specialvar = true
              else
                specialvar = false
              end
            end
          end
        end
        if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          score*=0.5
        end
        if attacker.hp==attacker.totalhp && (attitemworks && attacker.item == PBItems::FOCUSSASH)
          score*=1.2
        else
          score*=0.8
          score*=0.8 if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
        end
        if attacker.lastMoveUsed==671
          score*=0.7
        end
        score*=0.6 if checkAImoves(PBStuff::SETUPMOVE,aimem)
        miniscore = attacker.hp*(1.0/attacker.totalhp)
        score*=miniscore
        if opponent.spatk > opponent.attack
          score*=0.3
        end
        score*=0.05 if checkAIbest(aimem,3,[],false,attacker,opponent,skill)
      when 0x16C # Shore Up
        if aimem.length > 0 && skill>=PBTrainerAI.bestSkill
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          if maxdam>attacker.hp
            if maxdam>(attacker.hp*1.5)
              score=0
            else
              score*=5
            #experimental -- cancels out drop if killing moves
              if initialscores.length>0
                score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
              end
              #end experimental
            end
          else
            if maxdam*1.5>attacker.hp
              score*=2
            end
            if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              if maxdam*2>attacker.hp
                score*=5
                #experimental -- cancels out drop if killing moves
                if initialscores.length>0
                  score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
                end
                #end experimental
              end
            end
          end
        elsif skill>=PBTrainerAI.bestSkill #no highest expected damage yet
          if ((attacker.hp.to_f)/attacker.totalhp)<0.5
            score*=3
            if ((attacker.hp.to_f)/attacker.totalhp)<0.25
              score*=3
            end
            #experimental -- cancels out drop if killing moves
            if initialscores.length>0
              score*=6 if hasgreatmoves(initialscores,scoreindex,skill)
            end
            #end experimental
          end
        elsif skill>=PBTrainerAI.mediumSkill
          score*=3 if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
        end
        score*=0.7 if opponent.moves.any? {|moveloop| (PBStuff::SETUPMOVE).include?(moveloop)}
        if (attacker.hp.to_f)/attacker.totalhp<0.5
          score*=1.5
          if attacker.effects[PBEffects::Curse]
            score*=2
          end
          if attacker.hp*4<attacker.totalhp
            if attacker.status==PBStatuses::POISON
              score*=1.5
            end
            if attacker.effects[PBEffects::LeechSeed]>=0
              score*=2
            end
            if attacker.hp<attacker.totalhp*0.13
              if attacker.status==PBStatuses::BURN
                score*=2
              end
              if (pbWeather==PBWeather::HAIL && !attacker.pbHasType?(:ICE)) || (pbWeather==PBWeather::SANDSTORM && !attacker.pbHasType?(:ROCK) && !attacker.pbHasType?(:GROUND) && !attacker.pbHasType?(:STEEL))
                score*=2
              end
            end
          end
        else
          score*=0.9
        end
        if attacker.effects[PBEffects::Toxic]>0
          score*=0.5
          if attacker.effects[PBEffects::Toxic]>4
            score*=0.5
          end
        end
        if attacker.status==PBStatuses::PARALYSIS || attacker.effects[PBEffects::Attract]>=0 || attacker.effects[PBEffects::Confusion]>0
          score*=1.1
        end
        if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::Curse]
          score*=1.3
          if opponent.effects[PBEffects::Toxic]>0
            score*=1.3
          end
        end
        score*=1.2 if checkAImoves(PBStuff::CONTRARYBAITMOVE,aimem)
        if opponent.vanished || opponent.effects[PBEffects::HyperBeam]>0
          score*=1.2
        end
        if pbWeather==PBWeather::SANDSTORM
          score*=1.5
        end
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==12 # Desert
            score*=1.3
          end
          if $fefieldeffect==20 # Ashen Beach
            score*=1.5
          end
          if $fefieldeffect==21 || $fefieldeffect==26 # (Murk)Water Surface
            if pbRoughStat(opponent,PBStats::ATTACK,skill)>pbRoughStat(opponent,PBStats::SPATK,skill)
              score*=1.5
            end
          end
        end
        if ((attacker.hp.to_f)/attacker.totalhp)>0.8
          score=0
        elsif ((attacker.hp.to_f)/attacker.totalhp)>0.6
          score*=0.6
        elsif ((attacker.hp.to_f)/attacker.totalhp)<0.25
          score*=2
        end
        if attacker.effects[PBEffects::Wish]>0
            score=0
        end
      when 0x16D # Sparkling Aria
        if opponent.status==PBStatuses::BURN
          score*=0.6
        end
      when 0x16E # Spectral Thief
        if opponent.effects[PBEffects::Substitute]>0
          score*=1.2
        end
        ministat= 10*statchangecounter(opponent,1,7)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::CONTRARY)
          ministat*=(-1)
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SIMPLE)
          ministat*=2
        end
        ministat+=100
        ministat/=100.0
        score*=ministat
      when 0x16F # Speed Swap
        if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          miniscore= (10)*opponent.stages[PBStats::SPEED]
          minimini= (-10)*attacker.stages[PBStats::SPEED]
          if miniscore==0 && minimini==0
            score*=0
          else
            miniscore+=minimini
            miniscore+=100
            miniscore/=100.0
            score*=miniscore
            if @doublebattle
              score*=0.8
            end
          end
        else
          score*=0
        end
      when 0x170 # Spotlight
        maxdam=0
        maxtype = -1
        contactcheck = false
        if aimem.length > 0
          for j in aimem
            tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)
            if tempdam>maxdam
              maxdam=tempdam
              maxtype = j.type
              contactcheck = j.isContactMove?
            end
          end
        end
        if @doublebattle && opponent==attacker.pbPartner
          if !opponent.abilitynulled
            if opponent.ability == PBAbilities::FLASHFIRE 
              score*=3 if checkAIbest(aimem,1,[PBTypes::FIRE],false,attacker,opponent,skill)
            elsif opponent.ability == PBAbilities::STORMDRAIN || opponent.ability == PBAbilities::DRYSKIN || opponent.ability == PBAbilities::WATERABSORB
              score*=3 if checkAIbest(aimem,1,[PBTypes::WATER],false,attacker,opponent,skill)
            elsif opponent.ability == PBAbilities::MOTORDRIVE || opponent.ability == PBAbilities::LIGHTNINGROD || opponent.ability == PBAbilities::VOLTABSORB
              score*=3 if checkAIbest(aimem,1,[PBTypes::ELECTRIC],false,attacker,opponent,skill)
            elsif opponent.ability == PBAbilities::SAPSIPPER
              score*=3 if checkAIbest(aimem,1,[PBTypes::GRASS],false,attacker,opponent,skill)
            end
          end
          if opponent.pbHasMove?((PBMoves::KINGSSHIELD)) || opponent.pbHasMove?((PBMoves::BANEFULBUNKER)) || opponent.pbHasMove?((PBMoves::SPIKYSHIELD))
            if checkAIbest(aimem,4,[],false,attacker,opponent,skill)
              score*=2
            end
          end
          if opponent.pbHasMove?((PBMoves::COUNTER)) || opponent.pbHasMove?((PBMoves::METALBURST)) || opponent.pbHasMove?((PBMoves::MIRRORCOAT))
            score*=2
          end
          if (attacker.pbSpeed<pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.5
          end
          if (attacker.pbSpeed<pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=1.5
          end
        else
          score=1
        end
      when 0x171 # Stomping Tantrum
        if $fefieldeffect==5
          psyvar=false
          for mon in pbParty(attacker.index)
            next if mon.nil?
            if mon.hasType?(:PSYCHIC)
              psyvar=true
            end
          end
          if !attacker.pbHasType?(:PSYCHIC)
            score*=1.3
          end
          if !psyvar
            score*=1.8
          else
            score*=0.7
          end
        end
      when 0x172 # Strength Sap
        if opponent.effects[PBEffects::Substitute]<=0
          if attacker.effects[PBEffects::HealBlock]>0
            score*=0
          else
            if checkAIdamage(aimem,attacker,opponent,skill)>attacker.hp
              score*=3
              if skill>=PBTrainerAI.bestSkill
                if checkAIdamage(aimem,attacker,opponent,skill)*1.5 > attacker.hp
                  score*=1.5
                end
                if (attacker.pbSpeed<pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0)
                  if checkAIdamage(aimem,attacker,opponent,skill)*2 > attacker.hp
                    score*=2
                  else
                    score*=0.2
                  end
                end
              end
            end
          end
          if opponent.pbHasMove?((PBMoves::CALMMIND)) || opponent.pbHasMove?((PBMoves::WORKUP)) || opponent.pbHasMove?((PBMoves::NASTYPLOT)) || opponent.pbHasMove?((PBMoves::TAILGLOW)) || opponent.pbHasMove?((PBMoves::GROWTH)) || opponent.pbHasMove?((PBMoves::QUIVERDANCE))
            score*=0.7
          end
          if (attacker.hp.to_f)/attacker.totalhp<0.5
            score*=1.5
          else
            score*=0.5
          end
          if !(roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL))
            score*=0.8
          end
          if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN || opponent.effects[PBEffects::LeechSeed]>=0 || opponent.effects[PBEffects::Curse]
            score*=1.3
            if opponent.effects[PBEffects::Toxic]>0
              score*=1.3
            end
          end
          score*=1.2 if checkAImoves(PBStuff::CONTRARYBAITMOVE,aimem)
          if opponent.vanished || opponent.effects[PBEffects::HyperBeam]>0
            score*=1.2
          end
          ministat = opponent.attack
          ministat/=(attacker.totalhp).to_f
          ministat+=0.5
          score*=ministat
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::LIQUIDOOZE)
            score*=0.2
          end
          if $fefieldeffect==15 || $fefieldeffect==8
            score*=1.3
          end
          if (attitemworks && attacker.item == PBItems::BIGROOT)
            score*=1.3
          end
          miniscore=100
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            miniscore*=1.3
          end
          count=-1
          party=pbParty(attacker.index)
          sweepvar=false
          for i in 0...party.length
            count+=1
            next if (count==attacker.pokemonIndex || party[i].nil?)
            temproles = pbGetMonRole(party[i],opponent,skill,count,party)
            if temproles.include?(PBMonRoles::SWEEPER)
              sweepvar=true
            end
          end
          if sweepvar
            miniscore*=1.1
          end
          livecount2=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount2+=1 if i.hp!=0
          end
          if livecount2==1 || (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || opponent.effects[PBEffects::MeanLook]>0
            miniscore*=1.4
          end
          if opponent.status==PBStatuses::POISON
            miniscore*=1.2
          end
          if opponent.stages[PBStats::ATTACK]<0
            minimini = 5*opponent.stages[PBStats::ATTACK]
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if attacker.pbHasMove?((PBMoves::FOULPLAY))
            miniscore*=0.5
          end
          if opponent.status==PBStatuses::BURN
            miniscore*=0.5
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE) || (!opponent.abilitynulled && opponent.ability == PBAbilities::COMPETITIVE)
            miniscore*=0.1
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::DEFIANT) || (!opponent.abilitynulled && opponent.ability == PBAbilities::CONTRARY)
            miniscore*=0.5
          end
          miniscore/=100.0
          if attacker.stages[PBStats::ATTACK]!=6
            score*=miniscore
          end
        else
          score = 0
        end
      when 0x173 # Throat Chop
        maxdam=0
        maxsound = false
        soundcheck = false
        if aimem.length > 0
          for j in aimem
            soundcheck=true if j.isSoundBased?
            tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)
            if tempdam>maxdam
              maxdam=tempdam
              maxsound = j.isSoundBased?
            end
          end
        end
        if maxsound
          score*=1.5
        else
          if soundcheck
            score*=1.3
          end
        end
      when 0x174 # Toxic Thread
        if opponent.pbCanPoison?(false)
          miniscore=100
          miniscore*=1.2
          ministat=0
          ministat+=opponent.stages[PBStats::DEFENSE]
          ministat+=opponent.stages[PBStats::SPDEF]
          ministat+=opponent.stages[PBStats::EVASION]
          if ministat>0
            minimini=5*ministat
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::NATURALCURE)
            miniscore*=0.3
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::MARVELSCALE)
            miniscore*=0.7
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::TOXICBOOST) || (!opponent.abilitynulled && opponent.ability == PBAbilities::GUTS)
            miniscore*=0.2
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::POISONHEAL) || (!opponent.abilitynulled && opponent.ability == PBAbilities::MAGICGUARD)
            miniscore*=0.1
          end
          miniscore*=0.2 if checkAImoves([PBMoves::FACADE],aimem)
          miniscore*=0.1 if checkAImoves([PBMoves::REST],aimem)
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            miniscore*=1.5
          end
          if initialscores.length>0
            miniscore*=1.2 if hasbadmoves(initialscores,scoreindex,30)
          end
          if attacker.pbHasMove?((PBMoves::VENOSHOCK)) ||
            attacker.pbHasMove?((PBMoves::VENOMDRENCH)) ||
            (!attacker.abilitynulled && attacker.ability == PBAbilities::MERCILESS)
            miniscore*=1.6
          end
          if opponent.effects[PBEffects::Yawn]>0
            miniscore*=0.4
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SHEDSKIN)
            miniscore*=0.7
          end
          miniscore/=100.0
          score*=miniscore
        else
          score*=0.5
        end
        if opponent.stages[PBStats::SPEED]>0 || opponent.stages[PBStats::SPEED]==-6
          score*=0.5
        else
          miniscore=100
          if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
            miniscore*=1.1
          end
          livecount1=0
          for i in pbParty(attacker.index)
            next if i.nil?
            livecount1+=1 if i.hp!=0
          end
          livecount2=0
          for i in pbParty(opponent.index)
            next if i.nil?
            livecount2+=1 if i.hp!=0
          end
          if livecount2==1 || (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || opponent.effects[PBEffects::MeanLook]>0
            miniscore*=1.4
          end
          if opponent.stages[PBStats::SPEED]<0
            minimini = 5*opponent.stages[PBStats::SPEED]
            minimini+=100
            minimini/=100.0
            miniscore*=minimini
          end
          if livecount1==1
            miniscore*=0.5
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE) || (!opponent.abilitynulled && opponent.ability == PBAbilities::COMPETITIVE) || (!opponent.abilitynulled && opponent.ability == PBAbilities::DEFIANT) || (!opponent.abilitynulled && opponent.ability == PBAbilities::CONTRARY)
            miniscore*=0.1
          end
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SPEEDBOOST)
            miniscore*=0.5
          end
          if attacker.pbHasMove?((PBMoves::ELECTROBALL))
            miniscore*=1.5
          end
          if attacker.pbHasMove?((PBMoves::GYROBALL))
            miniscore*=0.5
          end
          miniscore*=0.1 if  @trickroom!=0 || checkAImoves([PBMoves::TRICKROOM],aimem)
          if (oppitemworks && opponent.item == PBItems::LAGGINGTAIL) || (oppitemworks && opponent.item == PBItems::IRONBALL)
            miniscore*=0.1
          end
          miniscore*=1.3 if checkAImoves([PBMoves::ELECTROBALL],aimem)
          miniscore*=0.5 if checkAImoves([PBMoves::GYROBALL],aimem)
          if (attacker.pbSpeed>pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0)
            score*=0.5
          end
          miniscore/=100.0
          score*=miniscore
        end
      when 0x175 # Mind Blown
        startscore = score
        maxdam = checkAIdamage(aimem,attacker,opponent,skill)
        if (!(!attacker.abilitynulled && attacker.ability == PBAbilities::MAGICGUARD) && attacker.hp<attacker.totalhp*0.5) || (attacker.hp<attacker.totalhp*0.75 && ((opponent.pbSpeed>attacker.pbSpeed) ^ (@trickroom!=0))) ||  $fefieldeffect==3 || $fefieldeffect==8 || pbCheckGlobalAbility(:DAMP)
          score*=0
          if !(!attacker.abilitynulled && attacker.ability == PBAbilities::MAGICGUARD)
            score*=0.7
            if startscore < 100
              score*=0.7
            end
            if (attacker.pbSpeed<pbRoughStat(opponent.pbPartner,PBStats::SPEED,skill)) ^ (@trickroom!=0)
              score*=0.5
            end
            if maxdam < attacker.totalhp*0.2
              score*=1.3
            end
            healcheck = false
            for m in attacker.moves
              healcheck=true if m.isHealingMove?
              break
            end
            if healcheck
              score*=1.2
            end
            if initialscores.length>0
              score*=1.3 if hasbadmoves(initialscores,scoreindex,25)
            end
            score*=0.5 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
            ministat=0
            ministat+=opponent.stages[PBStats::EVASION]
            minimini=(-10)*ministat
            minimini+=100
            minimini/=100.0
            score*=minimini
            ministat=0
            ministat+=attacker.stages[PBStats::ACCURACY]
            minimini=(10)*ministat
            minimini+=100
            minimini/=100.0
            score*=minimini
            if (oppitemworks && opponent.item == PBItems::LAXINCENSE) || (oppitemworks && opponent.item == PBItems::BRIGHTPOWDER)
              score*=0.7
            end
            if ((!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL) && pbWeather==PBWeather::SANDSTORM) || ((!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK) && pbWeather==PBWeather::HAIL)
              score*=0.7
            end
          else
            score*=1.1
          end
          firevar=false
          grassvar=false
          bugvar=false
          poisonvar=false
          icevar=false
          for mon in pbParty(attacker.index)
            next if mon.nil?
            if mon.hasType?(:FIRE)
              firevar=true
            end
            if mon.hasType?(:GRASS)
              grassvar=true
            end
            if mon.hasType?(:BUG)
              bugvar=true
            end
            if mon.hasType?(:POISON)
              poisonvar=true
            end
            if mon.hasType?(:ICE)
              icevar=true
            end
          end
          if $fefieldeffect==2 || $fefieldeffect==15 || ($fefieldeffect==33 && $fecounter>1)
            if firevar && !bugvar && !grassvar
              score*=2
            end
          elsif $fefieldeffect==16
            if firevar
              score*=2
            end
          elsif $fefieldeffect==11
            if !poisonvar
              score*=1.2
            end
            if attacker.hp*5 < attacker.totalhp
              score*=2
            end
            if opponent.pbNonActivePokemonCount==0
              score*=5
            end
          elsif $fefieldeffect==13 || $fefieldeffect==28
            if !icevar
              score*=1.5
            end
          end
        end
      when 0x176 # Photon Geyser
        damcount = 0
        firemove = false
        for m in attacker.moves
          if m.basedamage>0
            damcount+=1
            if m.type==(PBTypes::FIRE)
              firemove = true
            end
          end
        end
        if !opponent.moldbroken
          if (!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL)
            if pbWeather!=PBWeather::SANDSTORM
              score*=1.1
            end
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::VOLTABSORB) || (!opponent.abilitynulled && opponent.ability == PBAbilities::LIGHTNINGROD)
            if move.type==(PBTypes::ELECTRIC)
              if damcount==1
                score*=3
              end
              if PBTypes.getCombinedEffectiveness((PBTypes::ELECTRIC),opponent.type1,opponent.type2)>4
                score*=2
              end
            end
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::WATERABSORB) || (!opponent.abilitynulled && opponent.ability == PBAbilities::STORMDRAIN) || (!opponent.abilitynulled && opponent.ability == PBAbilities::DRYSKIN)
            if move.type==(PBTypes::WATER)
              if damcount==1
                score*=3
              end
              if PBTypes.getCombinedEffectiveness((PBTypes::WATER),opponent.type1,opponent.type2)>4
                score*=2
              end
            end
            if (!opponent.abilitynulled && opponent.ability == PBAbilities::DRYSKIN) && firemove
              score*=0.5
            end
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::FLASHFIRE)
            if move.type==(PBTypes::FIRE)
              if damcount==1
                score*=3
              end
              if PBTypes.getCombinedEffectiveness((PBTypes::FIRE),opponent.type1,opponent.type2)>4
                score*=2
              end
            end
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::LEVITATE)
            if move.type==(PBTypes::GROUND)
              if damcount==1
                score*=3
              end
              if PBTypes.getCombinedEffectiveness((PBTypes::GROUND),opponent.type1,opponent.type2)>4
                score*=2
              end
            end
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::WONDERGUARD)
            score*=5
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::SOUNDPROOF)
            if move.isSoundBased?
              score*=3
            end
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::THICKFAT)
            if move.type==(PBTypes::FIRE) || move.type==(PBTypes::ICE)
              score*=1.5
            end
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::MOLDBREAKER)
            score*=1.1
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
            score*=1.7
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::MULTISCALE)
            if attacker.hp==attacker.totalhp
              score*=1.5
            end
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::SAPSIPPER)
            if move.type==(PBTypes::GRASS)
              if damcount==1
                score*=3
              end
              if PBTypes.getCombinedEffectiveness((PBTypes::GRASS),opponent.type1,opponent.type2)>4
                score*=2
              end
            end
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK)
            if pbWeather!=PBWeather::HAIL
              score*=1.1
            end
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::FURCOAT)
            if attacker.attack>attacker.spatk
              score*=1.5
            end
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::FLUFFY)
            score*=1.5
            if move.type==(PBTypes::FIRE)
              score*=0.5
            end
          elsif (!opponent.abilitynulled && opponent.ability == PBAbilities::WATERBUBBLE)
            score*=1.5
            if move.type==(PBTypes::FIRE)
              score*=1.3
            end
          end
        end
      when 0x177 # Plasma Fists
        maxdam = 0
        maxtype = -1
        if aimem.length > 0
          for j in aimem
            tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)
            if tempdam>maxdam
              maxdam=tempdam
              maxtype = j.type
            end
          end
        end
        if (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
          miniscore=100
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::VOLTABSORB)
            if attacker.hp<attacker.totalhp*0.8
              miniscore*=1.5
            end
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::LIGHTNINGROD)
            if attacker.spatk > attacker.attack && attacker.stages[PBStats::SPATK]!=6
              miniscore*=1.5
            end
          end
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::MOTORDRIVE)
            if attacker.stages[PBStats::SPEED]!=6
              miniscore*=1.2
            end
          end
          if attacker.pbHasType?(:GROUND)
            miniscore*=1.3
          end
          miniscore*=0.5 if checkAIpriority(aimem)
          if maxtype == (PBTypes::NORMAL)
            miniscore*=2 
          end
          score*=miniscore
        end

      end
    ###### END FUNCTION CODES
    if (!opponent.abilitynulled && opponent.ability == PBAbilities::DANCER)
      if (PBStuff::DANCEMOVE).include?(move.id)
        score*=0.5
        score*=0.1 if $fefieldeffect==6
      end
    end
    ioncheck = false
    destinycheck = false
    widecheck = false
    powdercheck = false
    shieldcheck = false
    if skill>=PBTrainerAI.highSkill
      for j in aimem
        ioncheck = true if j.id==(PBMoves::IONDELUGE)
        destinycheck = true if j.id==(PBMoves::DESTINYBOND)
        widecheck = true if j.id==(PBMoves::WIDEGUARD)
        powdercheck = true if j.id==(PBMoves::POWDER)
        shieldcheck = true if j.id==(PBMoves::SPIKYSHIELD) ||
        j.id==(PBMoves::KINGSSHIELD) ||  j.id==(PBMoves::BANEFULBUNKER)
      end
      if @doublebattle && @aiMoveMemory[2][opponent.pbPartner.pokemonIndex].length>0
        for j in @aiMoveMemory[2][opponent.pbPartner.pokemonIndex]
          widecheck = true if j.id==(PBMoves::WIDEGUARD)
          powdercheck = true if j.id==(PBMoves::POWDER)
        end
      end
    end
    if ioncheck == true
      if move.type == 0
        if (!opponent.pbPartner.abilitynulled && opponent.pbPartner.ability == PBAbilities::LIGHTNINGROD) || (!opponent.abilitynulled && opponent.ability == PBAbilities::LIGHTNINGROD) ||
          (!opponent.abilitynulled && opponent.ability == PBAbilities::VOLTABSORB) || (!opponent.abilitynulled && opponent.ability == PBAbilities::MOTORDRIVE)
          score *= 0.3
        end
      end
    end
    if (move.target==PBTargets::SingleNonUser || move.target==PBTargets::RandomOpposing || move.target==PBTargets::AllOpposing || move.target==PBTargets::SingleOpposing || move.target==PBTargets::OppositeOpposing)
      if move.type==13 || (ioncheck == true && move.type == 0)
        if (!opponent.pbPartner.abilitynulled && opponent.pbPartner.ability == PBAbilities::LIGHTNINGROD)
          score*=0
        elsif (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::LIGHTNINGROD)
          score*=0.3
        end
      elsif move.type==11
        if (!opponent.pbPartner.abilitynulled && opponent.pbPartner.ability == PBAbilities::LIGHTNINGROD)
          score*=0
        elsif (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::LIGHTNINGROD)
          score*=0.3
        end
      end
    end
    if move.isSoundBased?
      if ((!opponent.abilitynulled && opponent.ability == PBAbilities::SOUNDPROOF) && !opponent.moldbroken) || attacker.effects[PBEffects::ThroatChop]!=0
        score*=0
      else
        score *= 0.6 if checkAImoves([PBMoves::THROATCHOP],aimem)
      end
    end
    if move.flags&0x80!=0 # Boosted crit moves
      if !((!opponent.abilitynulled && opponent.ability == PBAbilities::SHELLARMOR) || (!opponent.abilitynulled && opponent.ability == PBAbilities::BATTLEARMOR) || attacker.effects[PBEffects::LaserFocus]>0)
        boostercount = 0
        if move.pbIsPhysical?(move.type)
          boostercount += opponent.stages[PBStats::DEFENSE] if opponent.stages[PBStats::DEFENSE]>0
          boostercount -= attacker.stages[PBStats::ATTACK] if attacker.stages[PBStats::ATTACK]<0
        elsif move.pbIsSpecial?(move.type)
          boostercount += opponent.stages[PBStats::SPDEF] if opponent.stages[PBStats::SPDEF]>0
          boostercount -= attacker.stages[PBStats::SPATK] if attacker.stages[PBStats::SPATK]<0
        end
        score*=(1.05**boostercount)
      end
    end
    if move.basedamage>0
      if skill>=PBTrainerAI.highSkill
        if opponent.effects[PBEffects::DestinyBond]
          score*=0.2
        else
          if ((opponent.pbSpeed>attacker.pbSpeed) ^ (@trickroom!=0)) && destinycheck
            score*=0.7
          end
        end
      end
    end
    if widecheck && ((move.target == PBTargets::AllOpposing) || (move.target == PBTargets::AllNonUsers))
      score*=0.2
    end
    if powdercheck && move.type==10
      score*=0.2
    end
    if move.isContactMove? && !(attacker.item == PBItems::PROTECTIVEPADS) && !(!attacker.abilitynulled && attacker.ability == PBAbilities::LONGREACH)
      if (oppitemworks && opponent.item == PBItems::ROCKYHELMET) || shieldcheck
        score*=0.85
      end
      if !opponent.abilitynulled
        if opponent.ability == PBAbilities::ROUGHSKIN || opponent.ability == PBAbilities::IRONBARBS
          score*=0.85
        elsif opponent.ability == PBAbilities::EFFECTSPORE
          score*=0.75
        elsif opponent.ability == PBAbilities::FLAMEBODY && attacker.pbCanBurn?(false)
          score*=0.75
        elsif opponent.ability == PBAbilities::STATIC && attacker.pbCanParalyze?(false)
          score*=0.75
        elsif opponent.ability == PBAbilities::POISONPOINT && attacker.pbCanPoison?(false)
          score*=0.75
        elsif opponent.ability == PBAbilities::CUTECHARM && attacker.effects[PBEffects::Attract]<0
          if initialscores.length>0
            if initialscores[scoreindex] < 102
              score*=0.8
            end
          end
        elsif opponent.ability == PBAbilities::GOOEY || opponent.ability == PBAbilities::TANGLINGHAIR
          if attacker.pbCanReduceStatStage?(PBStats::SPEED)
            score*=0.9
            if ((pbRoughStat(opponent,PBStats::SPEED,skill)<attacker.pbSpeed) ^ (@trickroom!=0))
              score*=0.8
            end
          end
        elsif opponent.ability == PBAbilities::MUMMY
          if !attacker.abilitynulled && !((PBStuff::FIXEDABILITIES).include?(attacker.ability)) && !(attacker.ability == PBAbilities::MUMMY || attacker.ability == PBAbilities::SHIELDDUST)
            mummyscore = getAbilityDisruptScore(move,opponent,attacker,skill)
            if mummyscore < 2
              mummyscore = 2 - mummyscore
            else
              mummyscore = 0
            end
            score*=mummyscore
          end
        end
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::POISONTOUCH) && opponent.pbCanPoison?(false)
        score*=1.1
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::PICKPOCKET) && opponent.item!=0 && !pbIsUnlosableItem(opponent,opponent.item)
        score*=1.1
      end
      if opponent.effects[PBEffects::KingsShield]== true ||
      opponent.effects[PBEffects::BanefulBunker]== true ||
      opponent.effects[PBEffects::SpikyShield]== true
        score *=0.1
      end
    end
    if move.basedamage>0 && (opponent.effects[PBEffects::SpikyShield] ||
      opponent.effects[PBEffects::BanefulBunker] || opponent.effects[PBEffects::KingsShield])
      score*=0.1
    end
    if move.basedamage==0
      if hasgreatmoves(initialscores,scoreindex,skill)
        maxdam=checkAIdamage(aimem,attacker,opponent,skill)
        if maxdam>0 && maxdam<(attacker.hp*0.3)
          score*=0.6
        else
          score*=0.2 ### highly controversial, revert to 0.1 if shit sucks
        end
      end
    end
    ispowder = (move.id==214 || move.id==218 || move.id==220 || move.id==445 || move.id==600 || move.id==18 || move.id==219)
    if ispowder && (opponent.type==(PBTypes::GRASS) || (!opponent.abilitynulled && opponent.ability == PBAbilities::OVERCOAT) || (oppitemworks && opponent.item == PBItems::SAFETYGOGGLES))
      score*=0
    end
    # A score of 0 here means it should absolutely not be used
    if score<=0
      PBDebug.log(sprintf("%s: final score: 0",PBMoves.getName(move.id))) if $INTERNAL
      PBDebug.log(sprintf(" ")) if $INTERNAL
      attacker.pbUpdate(true) if defined?(megaEvolved) && megaEvolved==true #perry
      return score
    end
    ##### Other score modifications ################################################
    # Prefer damaging moves if AI has no more Pokémon
    if attacker.pbNonActivePokemonCount==0
      if skill>=PBTrainerAI.mediumSkill &&
        !(skill>=PBTrainerAI.highSkill && opponent.pbNonActivePokemonCount>0)
        if move.basedamage==0
          PBDebug.log("[Not preferring status move]") if $INTERNAL
          score*=0.9
        elsif opponent.hp<=opponent.totalhp/2.0
          PBDebug.log("[Preferring damaging move]") if $INTERNAL
          score*=1.1
        end
      end
    end
    # Don't prefer attacking the opponent if they'd be semi-invulnerable
    if opponent.effects[PBEffects::TwoTurnAttack]>0 &&
      skill>=PBTrainerAI.highSkill
      invulmove=$pkmn_move[opponent.effects[PBEffects::TwoTurnAttack]][0] #the function code of the current move
      if move.accuracy>0 &&   # Checks accuracy, i.e. targets opponent
        ([0xC9,0xCA,0xCB,0xCC,0xCD,0xCE].include?(invulmove) ||
        opponent.effects[PBEffects::SkyDrop]) &&
        ((attacker.pbSpeed>opponent.pbSpeed) ^ (@trickroom!=0))
        if skill>=PBTrainerAI.bestSkill   # Can get past semi-invulnerability
          miss=false
          case invulmove
            when 0xC9, 0xCC # Fly, Bounce
              miss=true unless move.function==0x08 ||  # Thunder
                              move.function==0x15 ||  # Hurricane
                              move.function==0x77 ||  # Gust
                              move.function==0x78 ||  # Twister
                              move.function==0x11B || # Sky Uppercut
                              move.function==0x11C || # Smack Down
                              (move.id == PBMoves::WHIRLWIND)
            when 0xCA # Dig
              miss=true unless move.function==0x76 || # Earthquake
                              move.function==0x95    # Magnitude
            when 0xCB # Dive
              miss=true unless move.function==0x75 || # Surf
                              move.function==0xD0 || # Whirlpool
                              move.function==0x12D   # Shadow Storm
            when 0xCD # Shadow Force
              miss=true
            when 0xCE # Sky Drop
              miss=true unless move.function==0x08 ||  # Thunder
                              move.function==0x15 ||  # Hurricane
                              move.function==0x77 ||  # Gust
                              move.function==0x78 ||  # Twister
                              move.function==0x11B || # Sky Uppercut
                              move.function==0x11C    # Smack Down
          end
          if opponent.effects[PBEffects::SkyDrop]
            miss=true unless move.function==0x08 ||  # Thunder
                            move.function==0x15 ||  # Hurricane
                            move.function==0x77 ||  # Gust
                            move.function==0x78 ||  # Twister
                            move.function==0x11B || # Sky Uppercut
                            move.function==0x11C    # Smack Down
          end
          score*=0 if miss
        else
          score*=0
        end
      end
    end
    # Pick a good move for the Choice items
    if attitemworks && (attacker.item == PBItems::CHOICEBAND || attacker.item == PBItems::CHOICESPECS || attacker.item == PBItems::CHOICESCARF)
      if move.basedamage==0 && move.function!=0xF2 # Trick
        score*=0.1
      end
      if ((move.type == PBTypes::NORMAL) && $fefieldeffect!=29) || (move.type == PBTypes::GHOST) || (move.type == PBTypes::FIGHTING) || (move.type == PBTypes::DRAGON) || (move.type == PBTypes::PSYCHIC) || (move.type == PBTypes::GROUND) || (move.type == PBTypes::ELECTRIC) || (move.type == PBTypes::POISON)
        score*=0.95
      end
      if (move.type == PBTypes::FIRE) || (move.type == PBTypes::WATER) || (move.type == PBTypes::GRASS) || (move.type == PBTypes::ELECTRIC)
        score*=0.95
      end
      if move.accuracy > 0
        miniacc = (move.accuracy/100.0)
        score *= miniacc
      end
      if move.pp < 6
        score *= 0.9
      end
    end
    #If user is frozen, prefer a move that can thaw the user
    if attacker.status==PBStatuses::FROZEN
      if skill>=PBTrainerAI.mediumSkill
        if move.canThawUser?
          score+=30
        else
          hasFreezeMove=false
          for m in attacker.moves
            if m.canThawUser?
              hasFreezeMove=true; break
            end
          end
          score*=0 if hasFreezeMove
        end
      end
    end
    # If target is frozen, don't prefer moves that could thaw them
    if opponent.status==PBStatuses::FROZEN
      if (move.type == PBTypes::FIRE)
        score *= 0.1
      end
    end
    # Adjust score based on how much damage it can deal
    if move.basedamage>0
      typemod=pbTypeModNoMessages(bettertype,attacker,opponent,move,skill)
      if typemod==0 || score<=0
        score=0
      elsif skill>=PBTrainerAI.mediumSkill && !(!attacker.abilitynulled && (attacker.ability == PBAbilities::MOLDBREAKER || attacker.ability == PBAbilities::TURBOBLAZE || attacker.ability == PBAbilities::TERAVOLT))
        if !opponent.abilitynulled
          if (typemod<=4 && opponent.ability == PBAbilities::WONDERGUARD) ||
            (move.type == PBTypes::GROUND && (opponent.ability == PBAbilities::LEVITATE || (oppitemworks && opponent.item == PBItems::AIRBALLOON) || opponent.effects[PBEffects::MagnetRise]>0)) ||
            (move.type == PBTypes::FIRE && opponent.ability == PBAbilities::FLASHFIRE) ||
            (move.type == PBTypes::WATER && (opponent.ability == PBAbilities::WATERABSORB || opponent.ability == PBAbilities::STORMDRAIN || opponent.ability == PBAbilities::DRYSKIN)) ||
            (move.type == PBTypes::GRASS && opponent.ability == PBAbilities::SAPSIPPER) ||
            (move.type == PBTypes::ELECTRIC)&& (opponent.ability == PBAbilities::VOLTABSORB || opponent.ability == PBAbilities::LIGHTNINGROD || opponent.ability == PBAbilities::MOTORDRIVE)
            score=0
          end
        end
      else
        if move.type == PBTypes::GROUND && (opponent.ability == PBAbilities::LEVITATE || (oppitemworks && opponent.item == PBItems::AIRBALLOON) || opponent.effects[PBEffects::MagnetRise]>0)
          score=0
        end
      end
      if score != 0
        # Calculate how much damage the move will do (roughly)
        realBaseDamage=move.basedamage
        realBaseDamage=60 if move.basedamage==1
        if skill>=PBTrainerAI.mediumSkill
          realBaseDamage=pbBetterBaseDamage(move,attacker,opponent,skill,realBaseDamage)
        end
      end
    else # non-damaging moves
      if !opponent.abilitynulled
        if (move.type == PBTypes::GROUND && (opponent.ability == PBAbilities::LEVITATE || (oppitemworks && opponent.item == PBItems::AIRBALLOON) || opponent.effects[PBEffects::MagnetRise]>0)) ||
          (move.type == PBTypes::FIRE && opponent.ability == PBAbilities::FLASHFIRE) ||
          (move.type == PBTypes::WATER && (opponent.ability == PBAbilities::WATERABSORB || opponent.ability == PBAbilities::STORMDRAIN || opponent.ability == PBAbilities::DRYSKIN)) ||
          (move.type == PBTypes::GRASS && opponent.ability == PBAbilities::SAPSIPPER) ||
          (move.type == PBTypes::ELECTRIC)&& (opponent.ability == PBAbilities::VOLTABSORB || opponent.ability == PBAbilities::LIGHTNINGROD || opponent.ability == PBAbilities::MOTORDRIVE)
          score=0
        end
      end
    end
    accuracy=pbRoughAccuracy(move,attacker,opponent,skill)
    score*=accuracy/100.0
    #score=0 if score<=10 && skill>=PBTrainerAI.highSkill
    if (move.basedamage==0 && !(move.id == PBMoves::NATUREPOWER)) &&
      (move.target==PBTargets::SingleNonUser || move.target==PBTargets::RandomOpposing || move.target==PBTargets::AllOpposing || move.target==PBTargets::OpposingSide || move.target==PBTargets::SingleOpposing || move.target==PBTargets::OppositeOpposing) &&
      ((!opponent.abilitynulled && opponent.ability == PBAbilities::MAGICBOUNCE) || (!opponent.pbPartner.abilitynulled && opponent.pbPartner.ability == PBAbilities::MAGICBOUNCE))
      score=0
    end
    if skill>=PBTrainerAI.mediumSkill
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::PRANKSTER)
        if opponent.pbHasType?(:DARK)
          if move.basedamage==0 && move.priority>-1
            score=0
          end
        end
      end
    end
    # Avoid shiny wild pokemon if you're an AI partner
    if pbIsWild?
      if attacker.index == 2
        if opponent.pokemon.isShiny?
          score *= 0.15
        end
      end
    end
    score=score.to_i
    score=0 if score<0
    PBDebug.log(sprintf("%s: final score: %d",PBMoves.getName(move.id),score)) if $INTERNAL
    PBDebug.log(sprintf(" ")) if $INTERNAL
    attacker.pbUpdate(true) if defined?(megaEvolved) && megaEvolved==true #perry
    return score
  end

  def pbRoughStat(battler,stat,skill)
    if skill>=PBTrainerAI.highSkill && stat==PBStats::SPEED
      return battler.pbSpeed
    end
    stagemul=[2,2,2,2,2,2,2,3,4,5,6,7,8]
    stagediv=[8,7,6,5,4,3,2,2,2,2,2,2,2]
    stage=battler.stages[stat]+6
    value=0
    value=battler.attack if stat==PBStats::ATTACK
    value=battler.defense if stat==PBStats::DEFENSE
    value=battler.speed if stat==PBStats::SPEED
    value=battler.spatk if stat==PBStats::SPATK
    value=battler.spdef if stat==PBStats::SPDEF
    return (value*1.0*stagemul[stage]/stagediv[stage]).floor
  end

  def pbBetterBaseDamage(move,attacker,opponent,skill,basedamage)
    # Covers all function codes which have their own def pbBaseDamage
    aimem = getAIMemory(skill,opponent.pokemonIndex)
    case move.function
      when 0x6A # SonicBoom
        basedamage=20
        if $fefieldeffect==9
          basedamage=140
        end
      when 0x6B # Dragon Rage
        basedamage=40
      when 0x6C # Super Fang
        basedamage=(opponent.hp/2.0).floor
        if (move.id == PBMoves::NATURESMADNESS) && ($fefieldeffect == 2 || $fefieldeffect == 15 || $fefieldeffect == 35)
          basedamage=(opponent.hp*0.75).floor
        elsif (move.id == PBMoves::NATURESMADNESS) && $fefieldeffect == 29
          basedamage=(opponent.hp*0.66).floor
        end
      when 0x6D # Night Shade
        basedamage=attacker.level
      when 0x6E # Endeavor
        basedamage=opponent.hp-attacker.hp
      when 0x6F # Psywave
        basedamage=attacker.level
      when 0x70 # OHKO
        basedamage=opponent.totalhp
      when 0x71 # Counter
        maxdam=60
        if aimem.length > 0
          for j in aimem
            next if j.pbIsSpecial?(j.type)
            next if j.basedamage<=1
            tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)*2
            if tempdam>maxdam
              maxdam=tempdam
            end
          end
        end
        basedamage = maxdam
      when 0x72 # Mirror Coat
        maxdam=60
        if aimem.length > 0
          for j in aimem
            next if j.pbIsPhysical?(j.type)
            next if j.basedamage<=1
            tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)*2
            if tempdam>maxdam
              maxdam=tempdam
            end
          end
        end
        basedamage = maxdam
      when 0x73 # Metal Burst
        maxdam=45
        if aimem.length > 0
          maxdam = checkAIdamage(aimem,attacker,opponent,skill)
        end
        basedamage = maxdam
      when 0x75, 0x12D # Surf, Shadow Storm
        basedamage*=2 if $pkmn_move[opponent.effects[PBEffects::TwoTurnAttack]][0] #the function code of the current move==0xCB # Dive
      when 0x76 # Earthquake
        basedamage*=2 if $pkmn_move[opponent.effects[PBEffects::TwoTurnAttack]][0] #the function code of the current move==0xCA # Dig
      when 0x77, 0x78 # Gust, Twister
        basedamage*=2 if $pkmn_move[opponent.effects[PBEffects::TwoTurnAttack]][0] #the function code of the current move==0xC9 || # Fly
                         $pkmn_move[opponent.effects[PBEffects::TwoTurnAttack]][0] #the function code of the current move==0xCC || # Bounce
                         $pkmn_move[opponent.effects[PBEffects::TwoTurnAttack]][0] #the function code of the current move==0xCE    # Sky Drop
      when 0x79 # Fusion Bolt
        basedamage*=2 if previousMove == 127 || previousMove == 131
      when 0x7A # Fusion Flare
        basedamage*=2 if previousMove == 64 || previousMove == 68
      when 0x7B # Venoshock
        if opponent.status==PBStatuses::POISON
          basedamage*=2
        elsif skill>=PBTrainerAI.bestSkill
          if $fefieldeffect==10 || $fefieldeffect==11 || $fefieldeffect==19 || $fefieldeffect==26 # Corrosive/Corromist/Wasteland/Murkwater
            basedamage*=2
          end
        end
      when 0x7C # SmellingSalt
        basedamage*=2 if opponent.status==PBStatuses::PARALYSIS  && opponent.effects[PBEffects::Substitute]<=0
      when 0x7D # Wake-Up Slap
        basedamage*=2 if opponent.status==PBStatuses::SLEEP && opponent.effects[PBEffects::Substitute]<=0
      when 0x7E # Facade
        basedamage*=2 if attacker.status==PBStatuses::POISON ||
                         attacker.status==PBStatuses::BURN ||
                         attacker.status==PBStatuses::PARALYSIS
      when 0x7F # Hex
        basedamage*=2 if opponent.status!=0
      when 0x80 # Brine
        basedamage*=2 if opponent.hp<=(opponent.totalhp/2.0).floor
      when 0x85 # Retaliate
        basedamage*=2 if attacker.pbOwnSide.effects[PBEffects::Retaliate]
      when 0x86 # Acrobatics
        basedamage*=2 if attacker.item ==0 || attacker.hasWorkingItem(:FLYINGGEM) ||
         $fefieldeffect == 6
      when 0x87 # Weather Ball
        basedamage*=2 if (pbWeather!=0 || $fefieldeffect==9)
      when 0x89 # Return
        basedamage=[(attacker.happiness*2/5).floor,1].max
      when 0x8A # Frustration
        basedamage=[((255-attacker.happiness)*2/5).floor,1].max
      when 0x8B # Eruption
        basedamage=[(150*(attacker.hp.to_f)/attacker.totalhp).floor,1].max
      when 0x8C # Crush Grip
        basedamage=[(120*(opponent.hp.to_f)/opponent.totalhp).floor,1].max
      when 0x8D # Gyro Ball
        ospeed=pbRoughStat(opponent,PBStats::SPEED,skill)
        aspeed=pbRoughStat(attacker,PBStats::SPEED,skill)
        basedamage=[[(25*ospeed/aspeed).floor,150].min,1].max
      when 0x8E # Stored Power
        mult=0
        for i in [PBStats::ATTACK,PBStats::DEFENSE,PBStats::SPEED,
                  PBStats::SPATK,PBStats::SPDEF,PBStats::ACCURACY,PBStats::EVASION]
          mult+=attacker.stages[i] if attacker.stages[i]>0
        end
        basedamage=20*(mult+1)
      when 0x8F # Punishment
        mult=0
        for i in [PBStats::ATTACK,PBStats::DEFENSE,PBStats::SPEED,
                  PBStats::SPATK,PBStats::SPDEF,PBStats::ACCURACY,PBStats::EVASION]
          mult+=opponent.stages[i] if opponent.stages[i]>0
        end
        basedamage=[20*(mult+3),200].min
      #when 0x90 # Hidden Power
      #hp=pbHiddenPower(attacker.iv)

      when 0x91 # Fury Cutter
        basedamage=basedamage<<(attacker.effects[PBEffects::FuryCutter]-1)
      when 0x92 # Echoed Voice
        basedamage*=attacker.effects[PBEffects::EchoedVoice]
      when 0x94 # Present
        basedamage=50
      when 0x95 # Magnitude
        basedamage=71
        basedamage*=2 if $pkmn_move[opponent.effects[PBEffects::TwoTurnAttack]][0] #the function code of the current move==0xCA # Dig
      when 0x96 # Natural Gift
        damagearray = PBStuff::NATURALGIFTDAMAGE
        haveanswer=false
        for i in damagearray.keys
          data=damagearray[i]
          if data
            for j in data
              if isConst?(attacker.item,PBItems,j)
                basedamage=i; haveanswer=true; break
              end
            end
          end
          break if haveanswer
        end
      when 0x97 # Trump Card
        dmgs=[200,80,60,50,40]
        ppleft=[move.pp-1,4].min   # PP is reduced before the move is used
        basedamage=dmgs[ppleft]
      when 0x98 # Flail
        n=(48*(attacker.hp.to_f)/attacker.totalhp).floor
        basedamage=20
        basedamage=40 if n<33
        basedamage=80 if n<17
        basedamage=100 if n<10
        basedamage=150 if n<5
        basedamage=200 if n<2
      when 0x99 # Electro Ball
        n=(attacker.pbSpeed/opponent.pbSpeed).floor
        basedamage=40
        basedamage=60 if n>=1
        basedamage=80 if n>=2
        basedamage=120 if n>=3
        basedamage=150 if n>=4
      when 0x9A # Low Kick
        weight=opponent.weight
        basedamage=20
        basedamage=40 if weight>100
        basedamage=60 if weight>250
        basedamage=80 if weight>500
        basedamage=100 if weight>1000
        basedamage=120 if weight>2000
      when 0x9B # Heavy Slam
        n=(attacker.weight/opponent.weight).floor
        basedamage=40
        basedamage=60 if n>=2
        basedamage=80 if n>=3
        basedamage=100 if n>=4
        basedamage=120 if n>=5
      when 0xA0 # Frost Breath
        basedamage*=1.5
      when 0xBD, 0xBE # Double Kick, Twineedle
        basedamage*=2
      when 0xBF # Triple Kick
        basedamage*=6
      when 0xC0 # Fury Attack
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::SKILLLINK)
          basedamage*=5
        else
          basedamage=(basedamage*19/6).floor
        end
      when 0xC1 # Beat Up
        party=pbParty(attacker.index)
        mult=0
        for i in 0...party.length
          mult+=1 if party[i] && !party[i].isEgg? &&
                      party[i].hp>0 && party[i].status==0
        end
        basedamage*=mult
      when 0xC4 # SolarBeam
        if pbWeather!=0 && pbWeather!=PBWeather::SUNNYDAY
          basedamage=(basedamage*0.5).floor
        end
      when 0xD0 # Whirlpool
        if skill>=PBTrainerAI.mediumSkill
          basedamage*=2 if $pkmn_move[opponent.effects[PBEffects::TwoTurnAttack]][0] #the function code of the current move==0xCB # Dive
        end
      when 0xD3 # Rollout
        if skill>=PBTrainerAI.mediumSkill
          basedamage*=2 if attacker.effects[PBEffects::DefenseCurl]
        end
      when 0xD4 # Bide
        maxdam=30
        if skill>=PBTrainerAI.bestSkill
          if aimem.length > 0
            maxdam = checkAIdamage(aimem,attacker,opponent,skill)
          end
        end
        basedamage = maxdam
      when 0xE1 # Final Gambit
        basedamage=attacker.hp
      when 0xF0 # Knock Off
        if opponent.item!=0 && !pbIsUnlosableItem(opponent,opponent.item)
          basedamage*=1.5
        end
      when 0xF7 # Fling
        if attacker.item ==0
          basedamage=0
        else
          basedamage=10 if pbIsBerry?(attacker.item)
          flingarray = PBStuff::FLINGDAMAGE
          for i in flingarray.keys
            data=flingarray[i]
            if data
              for j in data
                basedamage = i if isConst?(attacker.item,PBItems,j)
              end
            end
          end
        end
      when 0x113 # Spit Up
        basedamage = 100*attacker.effects[PBEffects::Stockpile]
      when 0x171 # Stomping Tantrum
        if attacker.effects[PBEffects::Tantrum]
          basedamage*=2
        end
    end
    return basedamage
  end

  def pbStatusDamage(move)
    if (move.id == PBMoves::AFTERYOU || move.id == PBMoves::BESTOW ||
      move.id == PBMoves::CRAFTYSHIELD || move.id == PBMoves::LUCKYCHANT ||
      move.id == PBMoves::MEMENTO || move.id == PBMoves::QUASH ||
      move.id == PBMoves::SAFEGUARD || move.id == PBMoves::SPITE ||
      move.id == PBMoves::SPLASH || move.id == PBMoves::SWEETSCENT ||
      move.id == PBMoves::TELEKINESIS || move.id == PBMoves::TELEPORT)
      return 0
    elsif (move.id == PBMoves::ALLYSWITCH || move.id == PBMoves::AROMATICMIST ||
      move.id == PBMoves::CONVERSION || move.id == PBMoves::ENDURE ||
      move.id == PBMoves::ENTRAINMENT || move.id == PBMoves::FLOWERSHIELD ||
      move.id == PBMoves::FORESIGHT || move.id == PBMoves::FORESTSCURSE ||
      move.id == PBMoves::GRAVITY || move.id == PBMoves::DEFOG ||
      move.id == PBMoves::GUARDSWAP || move.id == PBMoves::HEALBLOCK ||
      move.id == PBMoves::IMPRISON || move.id == PBMoves::INSTRUCT ||
      move.id == PBMoves::FAIRYLOCK || move.id == PBMoves::LASERFOCUS ||
      move.id == PBMoves::HELPINGHAND || move.id == PBMoves::MAGICROOM ||
      move.id == PBMoves::MAGNETRISE || move.id == PBMoves::SOAK ||
      move.id == PBMoves::LOCKON || move.id == PBMoves::MINDREADER ||
      move.id == PBMoves::MIRACLEEYE || move.id == PBMoves::MUDSPORT ||
      move.id == PBMoves::NIGHTMARE || move.id == PBMoves::ODORSLEUTH ||
      move.id == PBMoves::POWERSPLIT || move.id == PBMoves::POWERSWAP ||
      move.id == PBMoves::GRUDGE || move.id == PBMoves::GUARDSPLIT ||
      move.id == PBMoves::POWERTRICK || move.id == PBMoves::QUICKGUARD ||
      move.id == PBMoves::RECYCLE || move.id == PBMoves::REFLECTTYPE ||
      move.id == PBMoves::ROTOTILLER || move.id == PBMoves::SANDATTACK ||
      move.id == PBMoves::SKILLSWAP || move.id == PBMoves::SNATCH ||
      move.id == PBMoves::MAGICCOAT || move.id == PBMoves::SPEEDSWAP ||
      move.id == PBMoves::SPOTLIGHT || move.id == PBMoves::SWALLOW ||
      move.id == PBMoves::TEETERDANCE || move.id == PBMoves::WATERSPORT ||
      move.id == PBMoves::WIDEGUARD || move.id == PBMoves::WONDERROOM)
      return 5
    elsif (move.id == PBMoves::ACUPRESSURE || move.id == PBMoves::CAMOUFLAGE ||
      move.id == PBMoves::CHARM || move.id == PBMoves::CONFIDE ||
      move.id == PBMoves::DEFENSECURL || move.id == PBMoves::GROWTH ||
      move.id == PBMoves::EMBARGO || move.id == PBMoves::FLASH ||
      move.id == PBMoves::FOCUSENERGY || move.id == PBMoves::GROWL ||
      move.id == PBMoves::HARDEN || move.id == PBMoves::HAZE ||
      move.id == PBMoves::HONECLAWS || move.id == PBMoves::HOWL ||
      move.id == PBMoves::KINESIS || move.id == PBMoves::LEER ||
      move.id == PBMoves::METALSOUND || move.id == PBMoves::NOBLEROAR ||
      move.id == PBMoves::PLAYNICE || move.id == PBMoves::POWDER ||
      move.id == PBMoves::PSYCHUP || move.id == PBMoves::SHARPEN ||
      move.id == PBMoves::SMOKESCREEN || move.id == PBMoves::STRINGSHOT ||
      move.id == PBMoves::SUPERSONIC || move.id == PBMoves::TAILWHIP ||
      move.id == PBMoves::TEARFULLOOK || move.id == PBMoves::TORMENT ||
      move.id == PBMoves::WITHDRAW || move.id == PBMoves::WORKUP)
      return 10
    elsif (move.id == PBMoves::ASSIST || move.id == PBMoves::BABYDOLLEYES ||
      move.id == PBMoves::CAPTIVATE || move.id == PBMoves::COTTONSPORE ||
      move.id == PBMoves::DARKVOID || move.id == PBMoves::AGILITY ||
      move.id == PBMoves::DOUBLETEAM || move.id == PBMoves::EERIEIMPULSE ||
      move.id == PBMoves::FAKETEARS || move.id == PBMoves::FEATHERDANCE ||
      move.id == PBMoves::FLORALHEALING || move.id == PBMoves::GRASSWHISTLE ||
      move.id == PBMoves::HEALPULSE || move.id == PBMoves::HEALINGWISH ||
      move.id == PBMoves::HYPNOSIS || move.id == PBMoves::INGRAIN ||
      move.id == PBMoves::LUNARDANCE || move.id == PBMoves::MEFIRST ||
      move.id == PBMoves::MEDITATE || move.id == PBMoves::MIMIC ||
      move.id == PBMoves::PARTINGSHOT || move.id == PBMoves::POISONPOWDER ||
      move.id == PBMoves::REFRESH || move.id == PBMoves::ROLEPLAY ||
      move.id == PBMoves::SCARYFACE || move.id == PBMoves::SCREECH ||
      move.id == PBMoves::SING || move.id == PBMoves::SKETCH ||
      move.id == PBMoves::TICKLE || move.id == PBMoves::CHARGE ||
      move.id == PBMoves::TRICKORTREAT || move.id == PBMoves::VENOMDRENCH ||
      move.id == PBMoves::GEARUP || move.id == PBMoves::MAGNETICFLUX ||
      move.id == PBMoves::SANDSTORM || move.id == PBMoves::HAIL ||
       move.id == PBMoves::SUNNYDAY || move.id == PBMoves::RAINDANCE)
      return 15
    elsif (move.id == PBMoves::AQUARING || move.id == PBMoves::BLOCK ||
      move.id == PBMoves::CONVERSION2 || move.id == PBMoves::ELECTRIFY ||
      move.id == PBMoves::FLATTER || move.id == PBMoves::GASTROACID ||
      move.id == PBMoves::HEARTSWAP || move.id == PBMoves::IONDELUGE ||
      move.id == PBMoves::MEANLOOK || move.id == PBMoves::LOVELYKISS ||
      move.id == PBMoves::METRONOME || move.id == PBMoves::COPYCAT ||
      move.id == PBMoves::MIRRORMOVE || move.id == PBMoves::MIST ||
      move.id == PBMoves::PERISHSONG || move.id == PBMoves::REST ||
      move.id == PBMoves::ROAR || move.id == PBMoves::SIMPLEBEAM ||
      move.id == PBMoves::SLEEPPOWDER || move.id == PBMoves::SPIDERWEB ||
      move.id == PBMoves::SWAGGER || move.id == PBMoves::SWEETKISS ||
      move.id == PBMoves::POISONGAS || move.id == PBMoves::TOXICTHREAD ||
      move.id == PBMoves::TRANSFORM || move.id == PBMoves::WHIRLWIND ||
      move.id == PBMoves::WORRYSEED || move.id == PBMoves::YAWN)
      return 20
    elsif (move.id == PBMoves::AMNESIA || move.id == PBMoves::ATTRACT ||
      move.id == PBMoves::BARRIER || move.id == PBMoves::BELLYDRUM ||
      move.id == PBMoves::CONFUSERAY || move.id == PBMoves::DESTINYBOND ||
      move.id == PBMoves::DETECT || move.id == PBMoves::DISABLE ||
      move.id == PBMoves::ACIDARMOR || move.id == PBMoves::COSMICPOWER ||
      move.id == PBMoves::COTTONGUARD || move.id == PBMoves::DEFENDORDER ||
      move.id == PBMoves::FOLLOWME || move.id == PBMoves::AUTOTOMIZE ||
      move.id == PBMoves::HEALORDER || move.id == PBMoves::IRONDEFENSE ||
      move.id == PBMoves::LEECHSEED || move.id == PBMoves::MILKDRINK ||
      move.id == PBMoves::MINIMIZE || move.id == PBMoves::MOONLIGHT ||
      move.id == PBMoves::MORNINGSUN || move.id == PBMoves::PAINSPLIT ||
      move.id == PBMoves::PROTECT || move.id == PBMoves::PSYCHOSHIFT ||
      move.id == PBMoves::RAGEPOWDER || move.id == PBMoves::ROOST ||
      move.id == PBMoves::RECOVER || move.id == PBMoves::ROCKPOLISH ||
      move.id == PBMoves::SHOREUP || move.id == PBMoves::SLACKOFF ||
      move.id == PBMoves::SOFTBOILED || move.id == PBMoves::STRENGTHSAP ||
      move.id == PBMoves::STOCKPILE || move.id == PBMoves::STUNSPORE ||
      move.id == PBMoves::SUBSTITUTE ||
      move.id == PBMoves::SWITCHEROO || move.id == PBMoves::SYNTHESIS ||
      move.id == PBMoves::TAUNT || move.id == PBMoves::TOPSYTURVY ||
      move.id == PBMoves::TOXIC || move.id == PBMoves::TRICK ||
      move.id == PBMoves::WILLOWISP || move.id == PBMoves::WISH)
      return 25
    elsif (move.id == PBMoves::BATONPASS || move.id == PBMoves::BULKUP ||
      move.id == PBMoves::CALMMIND || move.id == PBMoves::COIL ||
      move.id == PBMoves::CURSE || move.id == PBMoves::ELECTRICTERRAIN ||
      move.id == PBMoves::ENCORE || move.id == PBMoves::GLARE ||
      move.id == PBMoves::GRASSYTERRAIN || move.id == PBMoves::MISTYTERRAIN ||
      move.id == PBMoves::NATUREPOWER || move.id == PBMoves::PSYCHICTERRAIN ||
      move.id == PBMoves::PURIFY || move.id == PBMoves::SLEEPTALK ||
      move.id == PBMoves::SPIKES || move.id == PBMoves::STEALTHROCK ||
      move.id == PBMoves::SPIKYSHIELD || move.id == PBMoves::THUNDERWAVE ||
      move.id == PBMoves::TOXICSPIKES || move.id == PBMoves::TRICKROOM)
      return 30
    elsif (move.id == PBMoves::AROMATHERAPY || move.id == PBMoves::BANEFULBUNKER ||
      move.id == PBMoves::HEALBELL || move.id == PBMoves::KINGSSHIELD ||
      move.id == PBMoves::LIGHTSCREEN || move.id == PBMoves::MATBLOCK ||
      move.id == PBMoves::NASTYPLOT || move.id == PBMoves::REFLECT ||
      move.id == PBMoves::SWORDSDANCE || move.id == PBMoves::TAILGLOW ||
      move.id == PBMoves::TAILWIND)
      return 35
    elsif (move.id == PBMoves::DRAGONDANCE || move.id == PBMoves::GEOMANCY ||
      move.id == PBMoves::QUIVERDANCE || move.id == PBMoves::SHELLSMASH ||
      move.id == PBMoves::SHIFTGEAR)
      return 40
    elsif (move.id == PBMoves::AURORAVEIL || move.id == PBMoves::STICKYWEB ||
      move.id == PBMoves::SPORE)
      return 60
    end
  end

  def pbAegislashStats(aegi)
    if aegi.form==1
      return aegi
    else
      bladecheck = aegi.clone
      bladecheck.form = 1
      if $fefieldeffect==31 && bladecheck.stages[PBStats::ATTACK]<6
        bladecheck.stages[PBStats::ATTACK] += 1
      end
      return bladecheck
    end
  end

  def pbMegaStats(mon)
    if mon.isMega?
      return mon
    else
      megacheck = mon.clone
      megacheck.stages = mon.stages.clone
      megacheck.form = mon.getMegaForm
      return megacheck
    end
  end
  
  def pbChangeMove(move,attacker)
    move = PokeBattle_Move.pbFromPBMove(self,PBMove.new(move.id))
    case move.id
      when PBMoves::WEATHERBALL
        weather=pbWeather
        move.type=(PBTypes::NORMAL)
        move.type=PBTypes::FIRE if (weather==PBWeather::SUNNYDAY && !attacker.hasWorkingItem(:UTILITYUMBRELLA))
        move.type=PBTypes::WATER if (weather==PBWeather::RAINDANCE && !attacker.hasWorkingItem(:UTILITYUMBRELLA))
        move.type=PBTypes::ROCK if weather==PBWeather::SANDSTORM
        move.type=PBTypes::ICE if weather==PBWeather::HAIL
        if pbWeather !=0 || $fefieldeffect==9
          move.basedamage*=2 if move.basedamage == 50 
        end    
        
      when PBMoves::HIDDENPOWER
        if attacker
          move.type = move.pbBaseType(type)
        end
        
      when PBMoves::NATUREPOWER
        move=0
        case $fefieldeffect
          when 33
            if $fecounter == 4
              move=PBMoves::PETALBLIZZARD
            else
              move=PBMoves::GROWTH
            end
          else
            if $fefieldeffect > 0 && $fefieldeffect <= 37
              naturemoves = FieldEffects::NATUREMOVES
              move= naturemoves[$fefieldeffect]
            else
              move=PBMoves::TRIATTACK
            end
          end
        move = PokeBattle_Move.pbFromPBMove(self,PBMove.new(move))
      end
    return move
  end
      
  def pbRoughDamage(move,attacker,opponent,skill,basedamage)
    if opponent.species==0 || attacker.species==0
      return 0
    end
    move = pbChangeMove(move,attacker)
    basedamage = move.basedamage
    if move.basedamage==0
      return 0
    end
    #Temporarly mega-ing pokemon if it can    #perry
    if pbCanMegaEvolve?(attacker.index)
      attacker.pokemon.makeMega
      attacker.pbUpdate(true)
      attacker.form=attacker.startform
      megaEvolved=true 
    end
    if skill>=PBTrainerAI.highSkill
      basedamage = pbBetterBaseDamage(move,attacker,opponent,skill,basedamage)
    end
    if move.function==0x6A ||   # SonicBoom
       move.function==0x6B ||   # Dragon Rage
       move.function==0x6C ||   # Super Fang
       move.function==0x6D ||   # Night Shade
       move.function==0x6E ||   # Endeavor
       move.function==0x6F ||   # Psywave
       move.function==0x70 ||   # OHKO
       move.function==0x71 ||   # Counter
       move.function==0x72 ||   # Mirror Coat
       move.function==0x73 ||   # Metal Burst
       move.function==0xD4 ||   # Bide
       move.function==0xE1      # Final Gambit
      attacker.pbUpdate(true) if defined?(megaEvolved) && megaEvolved==true #un-mega pokemon #perry
      return basedamage
    end
    type=move.type
    # More accurate move type (includes Normalize, most type-changing moves, etc.)
    
    if skill>=PBTrainerAI.minimumSkill
      type=move.pbBaseType(type)
    end
    
    oppitemworks = opponent.itemWorks?
    attitemworks = attacker.itemWorks?

    # ATTACKING/BASE DAMAGE SECTION
    atk=pbRoughStat(attacker,PBStats::ATTACK,skill)
    if attacker.species==681
      originalform = attacker.form
      dummymon = pbAegislashStats(attacker)
      dummymon.pbUpdate
      atk=pbRoughStat(dummymon,PBStats::ATTACK,skill)
      dummymon.form = originalform
      dummymon.pbUpdate
    end
    if move.function==0x121 # Foul Play
      atk=pbRoughStat(opponent,PBStats::ATTACK,skill)
    end
    if type>=0 && move.pbIsSpecial?(type)
      atk=pbRoughStat(attacker,PBStats::SPATK,skill)
      if attacker.species==681
        originalform = attacker.form
        dummymon = pbAegislashStats(attacker)
        dummymon.pbUpdate
        atk=pbRoughStat(dummymon,PBStats::SPATK,skill)
        dummymon.form = originalform
        dummymon.pbUpdate
      end
      if move.function==0x121 # Foul Play
        atk=pbRoughStat(opponent,PBStats::SPATK,skill)
      end
      if $fefieldeffect == 24
        stagemul=[2,2,2,2,2,2,2,3,4,5,6,7,8]
        stagediv=[8,7,6,5,4,3,2,2,2,2,2,2,2]
        gl1 = pbRoughStat(attacker,PBStats::SPATK,skill)
        gl2 = pbRoughStat(attacker,PBStats::SPDEF,skill)
        gl3 = attacker.stages[PBStats::SPDEF]+6
        gl4 = attacker.stages[PBStats::SPATK]+6
        if attitemworks
          gl2 *= 1.5 if attacker.item == PBItems::ASSAULTVEST
          gl1 *= 1.5 if attacker.item == PBItems::CHOICESPECS
          gl2 *= 1.5 if attacker.item == PBItems::EVIOLITE && pbGetEvolvedFormData(attacker.species).length>0
          gl1 *= 2 if attacker.item == PBItems::DEEPSEATOOTH && attacker.species == PBSpecies::CLAMPERL
          gl1 *= 2 if attacker.item == PBItems::LIGHTBALL && attacker.species == PBSpecies::PIKACHU
          gl2 *= 2 if attacker.item == PBItems::DEEPSEASCALE && attacker.species == PBSpecies::CLAMPERL
          gl2 *= 1.5 if attacker.item == PBItems::METALPOWDER && attacker.species == PBSpecies::DITTO
        end
        if !attacker.abilitynulled
          gl1 *= 1.5 if attacker.ability == PBAbilities::FLAREBOOST && attacker.status==PBStatuses::BURN
          gl1 *= 1.5 if attacker.ability == PBAbilities::MINUS && (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::PLUS)
          gl1 *= 1.5 if attacker.ability == PBAbilities::PLUS && (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::MINUS)
          gl1 *= 1.5 if attacker.ability == PBAbilities::SOLARPOWER && pbWeather==PBWeather::SUNNYDAY
          gl2 *= 1.5 if attacker.ability == PBAbilities::FLOWERGIFT && pbWeather==PBWeather::SUNNYDAY
        end
        gl1 *= 1.3 if (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::BATTERY)
        gl1=(gl1*stagemul[gl4]/stagediv[gl4]).floor
        gl2=(gl2*stagemul[gl3]/stagediv[gl3]).floor
        if gl1 < gl2
          atk=pbRoughStat(attacker,PBStats::SPDEF,skill)
        end
      end
    end

    #Field effect base damage adjustment
    if skill>=PBTrainerAI.bestSkill
      case $fefieldeffect
      when 1 # Electric Field
        if (move.id == PBMoves::EXPLOSION || move.id == PBMoves::SELFDESTRUCT ||
          move.id == PBMoves::HURRICANE || move.id == PBMoves::SURF ||
          move.id == PBMoves::SMACKDOWN || move.id == PBMoves::MUDDYWATER ||
          move.id == PBMoves::THOUSANDARROWS)
          basedamage=(basedamage*1.5).round
        elsif (move.id == PBMoves::MAGNETBOMB || move.id == PBMoves::PLASMAFISTS)
          basedamage=(basedamage*2).round
        end
      when 2 # Grassy Field
        if (move.id == PBMoves::FAIRYWIND || move.id == PBMoves::SILVERWIND)
          basedamage=(basedamage*1.5).round
        elsif (move.id == PBMoves::MUDDYWATER || move.id == PBMoves::SURF || move.id == PBMoves::EARTHQUAKE ||
          move.id == PBMoves::MAGNITUDE || move.id == PBMoves::BULLDOZE)
          basedamage=(basedamage*0.5).round
        end
      when 3 # Misty Field
        if (move.id == PBMoves::FAIRYWIND || move.id == PBMoves::MYSTICALFIRE ||
          move.id == PBMoves::MOONBLAST || move.id == PBMoves::MAGICALLEAF ||
          move.id == PBMoves::DOOMDUMMY || move.id == PBMoves::ICYWIND ||
          move.id == PBMoves::MISTBALL || move.id == PBMoves::AURASPHERE ||
          move.id == PBMoves::STEAMERUPTION || move.id == PBMoves::DAZZLINGGLEAM||
          move.id == PBMoves::SILVERWIND || move.id == PBMoves::MOONGEISTBEAM)
          basedamage=(basedamage*1.5).round
        elsif (move.id == PBMoves::DARKPULSE || move.id == PBMoves::SHADOWBALL ||
          move.id == PBMoves::NIGHTDAZE)
          basedamage=(basedamage*0.5).round
        end
      when 4 # Dark Crystal Cavern
        if (move.id == PBMoves::DARKPULSE ||
          move.id == PBMoves::NIGHTDAZE || move.id == PBMoves::NIGHTSLASH ||
          move.id == PBMoves::SHADOWBALL || move.id == PBMoves::SHADOWPUNCH ||
          move.id == PBMoves::SHADOWCLAW || move.id == PBMoves::SHADOWSNEAK ||
          move.id == PBMoves::SHADOWFORCE || move.id == PBMoves::SHADOWBONE)
          basedamage=(basedamage*1.5).round
        elsif (move.id == PBMoves::AURORABEAM || move.id == PBMoves::SIGNALBEAM ||
          move.id == PBMoves::FLASHCANNON || move.id == PBMoves::LUSTERPURGE ||
          move.id == PBMoves::DAZZLINGGLEAM || move.id == PBMoves::MIRRORSHOT ||
          move.id == PBMoves::TECHNOBLAST || move.id == PBMoves::DOOMDUMMY ||
          move.id == PBMoves::POWERGEM || move.id == PBMoves::MOONGEISTBEAM)
          basedamage=(basedamage*1.5).round
        elsif (move.id == PBMoves::PRISMATICLASER)
          basedamage=(basedamage*2).round
        end
      when 5 # Chess Board
        if (move.id == PBMoves::STRENGTH || move.id == PBMoves::ANCIENTPOWER ||
          move.id == PBMoves::PSYCHIC)
          basedamage=(basedamage*1.5).round
          if (opponent.ability == PBAbilities::ADAPTABILITY) ||
            (opponent.ability == PBAbilities::ANTICIPATION) ||
            (opponent.ability == PBAbilities::SYNCHRONIZE) ||
            (opponent.ability == PBAbilities::TELEPATHY)
            basedamage=(basedamage*0.5).round
          end
          if (opponent.ability == PBAbilities::OBLIVIOUS) ||
            (opponent.ability == PBAbilities::KLUTZ) ||
            (opponent.ability == PBAbilities::UNAWARE) ||
            (opponent.ability == PBAbilities::SIMPLE) ||
            opponent.effects[PBEffects::Confusion]>0
            basedamage=(basedamage*2).round
          end
        end
        if (move.id == PBMoves::FEINT || move.id == PBMoves::FEINTATTACK ||
          move.id == PBMoves::FAKEOUT)
          basedamage=(basedamage*1.5).round
        end
      when 6 # Big Top
        if (((move.type == PBTypes::FIGHTING) && move.pbIsPhysical?(move.type)) ||
          move.id == PBMoves::STRENGTH || move.id == PBMoves::WOODHAMMER ||
          move.id == PBMoves::DUALCHOP || move.id == PBMoves::HEATCRASH ||
          move.id == PBMoves::SKYDROP || move.id == PBMoves::BULLDOZE ||
          move.id == PBMoves::ICICLECRASH || move.id == PBMoves::BODYSLAM ||
          move.id == PBMoves::STOMP || move.id == PBMoves::POUND ||
          move.id == PBMoves::SLAM || move.id == PBMoves::GIGAIMPACT ||
          move.id == PBMoves::SMACKDOWN || move.id == PBMoves::IRONTAIL ||
          move.id == PBMoves::METEORMASH || move.id == PBMoves::DRAGONRUSH ||
          move.id == PBMoves::CRABHAMMER || move.id == PBMoves::BOUNCE ||
          move.id == PBMoves::HEAVYSLAM || move.id == PBMoves::MAGNITUDE ||
          move.id == PBMoves::EARTHQUAKE || move.id == PBMoves::STOMPINGTANTRUM ||
          move.id == PBMoves::BRUTALSWING || move.id == PBMoves::HIGHHORSEPOWER ||
          move.id == PBMoves::ICEHAMMER || move.id == PBMoves::DRAGONHAMMER ||
          move.id == PBMoves::BLAZEKICK)
          if (!attacker.abilitynulled && attacker.ability == PBAbilities::HUGEPOWER) ||
            (!attacker.abilitynulled && attacker.ability == PBAbilities::GUTS) ||
            (!attacker.abilitynulled && attacker.ability == PBAbilities::PUREPOWER) ||
            (!attacker.abilitynulled && attacker.ability == PBAbilities::SHEERFORCE)
            basedamage=(basedamage*2.2).round
          else
            basedamage=(basedamage*1.2).round
          end
        end
        if (move.id == PBMoves::PAYDAY)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::VINEWHIP || move.id == PBMoves::POWERWHIP ||
          move.id == PBMoves::FIRELASH)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::FIERYDANCE || move.id == PBMoves::PETALDANCE ||
          move.id == PBMoves::REVELATIONDANCE)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::FLY || move.id == PBMoves::ACROBATICS)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::FIRSTIMPRESSION)
          basedamage=(basedamage*1.5).round
        end
        if move.isSoundBased?
          basedamage=(basedamage*1.5).round
        end
      when 7 # Burning Field
        if (move.id == PBMoves::SMOG || move.id == PBMoves::CLEARSMOG)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::SMACKDOWN || move.id == PBMoves::THOUSANDARROWS)
          basedamage=(basedamage*1.5).round
        end
      when 8 # Swamp Field
        if (move.id == PBMoves::MUDBOMB || move.id == PBMoves::MUDSHOT ||
          move.id == PBMoves::MUDSLAP || move.id == PBMoves::MUDDYWATER ||
          move.id == PBMoves::SURF || move.id == PBMoves::SLUDGEWAVE ||
          move.id == PBMoves::GUNKSHOT || move.id == PBMoves::BRINE ||
          move.id == PBMoves::SMACKDOWN || move.id == PBMoves::THOUSANDARROWS)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::EARTHQUAKE || move.id == PBMoves::MAGNITUDE ||
         move.id == PBMoves::BULLDOZE)
          basedamage=(basedamage*0.25).round
        end
      when 9 # Rainbow Field
        if (move.id == PBMoves::SILVERWIND || move.id == PBMoves::MYSTICALFIRE ||
          move.id == PBMoves::DRAGONPULSE || move.id == PBMoves::TRIATTACK ||
          move.id == PBMoves::SACREDFIRE || move.id == PBMoves::FIREPLEDGE ||
          move.id == PBMoves::WATERPLEDGE || move.id == PBMoves::GRASSPLEDGE ||
          move.id == PBMoves::AURORABEAM || move.id == PBMoves::JUDGMENT ||
          move.id == PBMoves::RELICSONG || move.id == PBMoves::HIDDENPOWER ||
          move.id == PBMoves::SECRETPOWER || move.id == PBMoves::WEATHERBALL ||
          move.id == PBMoves::MISTBALL || move.id == PBMoves::HEARTSTAMP ||
          move.id == PBMoves::MOONBLAST || move.id == PBMoves::ZENHEADBUTT ||
          move.id == PBMoves::SPARKLINGARIA || move.id == PBMoves::FLEURCANNON ||
          move.id == PBMoves::PRISMATICLASER)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::DARKPULSE || move.id == PBMoves::SHADOWBALL ||
          move.id == PBMoves::NIGHTDAZE)
          basedamage=(basedamage*0.5).round
        end
      when 10 # Corrosive Field
        if (move.id == PBMoves::SMACKDOWN || move.id == PBMoves::MUDSLAP ||
          move.id == PBMoves::MUDSHOT || move.id == PBMoves::MUDBOMB ||
          move.id == PBMoves::MUDDYWATER || move.id == PBMoves::WHIRLPOOL ||
          move.id == PBMoves::THOUSANDARROWS)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::ACID || move.id == PBMoves::ACIDSPRAY ||
          move.id == PBMoves::GRASSKNOT)
          basedamage=(basedamage*2).round
        end
      when 11 # Corrosive Mist Field
        if (move.id == PBMoves::BUBBLEBEAM || move.id == PBMoves::ACIDSPRAY ||
          move.id == PBMoves::BUBBLE || move.id == PBMoves::SMOG ||
          move.id == PBMoves::CLEARSMOG || move.id == PBMoves::SPARKLINGARIA)
          basedamage=(basedamage*1.5).round
        end
      when 12 # Desert Field
        if (move.id == PBMoves::NEEDLEARM || move.id == PBMoves::PINMISSILE ||
          move.id == PBMoves::DIG || move.id == PBMoves::SANDTOMB ||
          move.id == PBMoves::HEATWAVE || move.id == PBMoves::THOUSANDWAVES ||
          move.id == PBMoves::BURNUP)
          basedamage=(basedamage*1.5).round
        end
      when 13 # Icy Field
        if (move.id == PBMoves::SCALD || move.id == PBMoves::STEAMERUPTION)
          basedamage=(basedamage*0.5).round
        end
      when 14 # Rocky Field
        if (move.id == PBMoves::ROCKSMASH)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::ROCKCLIMB || move.id == PBMoves::STRENGTH ||
          move.id == PBMoves::MAGNITUDE || move.id == PBMoves::EARTHQUAKE ||
          move.id == PBMoves::BULLDOZE || move.id == PBMoves::ACCELEROCK)
          basedamage=(basedamage*1.5).round
        end
      when 15 # Forest Field
        if (move.id == PBMoves::CUT)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::ATTACKORDER)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::SURF || move.id == PBMoves::MUDDYWATER)
          basedamage=(basedamage*0.5).round
        end
      when 16 # Superheated Field
        if (move.id == PBMoves::SURF || move.id == PBMoves::MUDDYWATER ||
          move.id == PBMoves::WATERPLEDGE || move.id == PBMoves::WATERSPOUT ||
          move.id == PBMoves::SPARKLINGARIA)
          basedamage=(basedamage*0.625).round
        end
        if (move.id == PBMoves::SCALD || move.id == PBMoves::STEAMERUPTION)
        basedamage=(basedamage*1.667).round
        end
      when 17 # Factory Field
        if (move.id == PBMoves::FLASHCANNON || move.id == PBMoves::GYROBALL ||
          move.id == PBMoves::MAGNETBOMB || move.id == PBMoves::GEARGRIND)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::STEAMROLLER || move.id == PBMoves::TECHNOBLAST)
          basedamage=(basedamage*1.5).round
        end
      when 18 # Shortcircuit Field
        if (move.type == PBTypes::ELECTRIC)
          basedamage=(basedamage*1.2).round
        end
        if (move.id == PBMoves::DAZZLINGGLEAM)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::DARKPULSE ||
          move.id == PBMoves::NIGHTDAZE || move.id == PBMoves::NIGHTSLASH ||
          move.id == PBMoves::SHADOWBALL || move.id == PBMoves::SHADOWPUNCH ||
          move.id == PBMoves::SHADOWCLAW || move.id == PBMoves::SHADOWSNEAK ||
          move.id == PBMoves::SHADOWFORCE || move.id == PBMoves::SHADOWBONE)
          basedamage=(basedamage*1.3).round
        end
        if (move.id == PBMoves::SURF || move.id == PBMoves::MUDDYWATER ||
          move.id == PBMoves::MAGNETBOMB || move.id == PBMoves::GYROBALL ||
          move.id == PBMoves::FLASHCANNON || move.id == PBMoves::GEARGRIND)
          basedamage=(basedamage*1.5).round
        end
      when 19 # Wasteland
        if (move.id == PBMoves::OCTAZOOKA || move.id == PBMoves::SLUDGE ||
          move.id == PBMoves::GUNKSHOT || move.id == PBMoves::SLUDGEWAVE ||
          move.id == PBMoves::SLUDGEBOMB)
          basedamage=(basedamage*1.2).round
        end
        if (move.id == PBMoves::SPITUP)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::VINEWHIP || move.id == PBMoves::POWERWHIP)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::MUDSLAP || move.id == PBMoves::MUDBOMB ||
          move.id == PBMoves::MUDSHOT)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::EARTHQUAKE || move.id == PBMoves::MAGNITUDE ||
          move.id == PBMoves::BULLDOZE)
          basedamage=(basedamage*0.25).round
        end
      when 20 # Ashen Beach
        if (move.id == PBMoves::MUDSLAP || move.id == PBMoves::MUDSHOT ||
          move.id == PBMoves::MUDBOMB  || move.id == PBMoves::SANDTOMB)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::HIDDENPOWER || move.id == PBMoves::STRENGTH)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::LANDSWRATH || move.id == PBMoves::THOUSANDWAVES)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::PSYCHIC)
          basedamage=(basedamage*1.2).round
        end
        if (move.id == PBMoves::STOREDPOWER || move.id == PBMoves::ZENHEADBUTT ||
          move.id == PBMoves::FOCUSBLAST || move.id == PBMoves::AURASPHERE)
          basedamage=(basedamage*1.3).round
        end
        if (move.id == PBMoves::SURF|| move.id == PBMoves::MUDDYWATER)
          basedamage=(basedamage*1.5).round
        end
      when 21 # Water Surface
        if (move.id == PBMoves::SURF || move.id == PBMoves::MUDDYWATER ||
          move.id == PBMoves::WHIRLPOOL || move.id == PBMoves::DIVE)
          basedamage=(basedamage*1.5).round
        end
      when 22 # Underwater
        if (move.id == PBMoves::WATERPULSE)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::ANCHORSHOT)
          basedamage=(basedamage*2).round
        end
      when 23 # Cave
        if move.isSoundBased?
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::ROCKTOMB)
          basedamage=(basedamage*1.5).round
        end
      when 25 # Crystal Cavern
        if (move.id == PBMoves::AURORABEAM || move.id == PBMoves::SIGNALBEAM ||
          move.id == PBMoves::FLASHCANNON || move.id == PBMoves::LUSTERPURGE ||
          move.id == PBMoves::DAZZLINGGLEAM || move.id == PBMoves::MIRRORSHOT ||
          move.id == PBMoves::TECHNOBLAST || move.id == PBMoves::DOOMDUMMY ||
          move.id == PBMoves::MOONGEISTBEAM || move.id == PBMoves::PHOTONGEYSER)
          basedamage=(basedamage*1.3).round
        end
        if (move.id == PBMoves::POWERGEM || move.id == PBMoves::DIAMONDSTORM ||
          move.id == PBMoves::ANCIENTPOWER || move.id == PBMoves::JUDGMENT ||
          move.id == PBMoves::ROCKSMASH || move.id == PBMoves::ROCKTOMB ||
          move.id == PBMoves::STRENGTH || move.id == PBMoves::ROCKCLIMB ||
          move.id == PBMoves::MULTIATTACK)
          basedamage=(basedamage*1.5).round
        end
      when 26 # Murkwater Surface
        if (move.id == PBMoves::MUDBOMB || move.id == PBMoves::MUDSLAP ||
          move.id == PBMoves::MUDSHOT || move.id == PBMoves::SMACKDOWN ||
          move.id == PBMoves::ACID || move.id == PBMoves::ACIDSPRAY ||
          move.id == PBMoves::BRINE || move.id == PBMoves::THOUSANDWAVES)
          basedamage=(basedamage*1.5).round
        end
      when 27 # Mountain
        if (move.id == PBMoves::VITALTHROW || move.id == PBMoves::CIRCLETHROW ||
          move.id == PBMoves::STORMTHROW)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::OMINOUSWIND || move.id == PBMoves::ICYWIND ||
          move.id == PBMoves::SILVERWIND || move.id == PBMoves::TWISTER ||
          move.id == PBMoves::RAZORWIND || move.id == PBMoves::FAIRYWIND)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::OMINOUSWIND || move.id == PBMoves::ICYWIND ||
          move.id == PBMoves::SILVERWIND || move.id == PBMoves::TWISTER ||
          move.id == PBMoves::RAZORWIND || move.id == PBMoves::FAIRYWIND ||
          move.id == PBMoves::GUST) && pbWeather==PBWeather::STRONGWINDS
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::THUNDER || move.id == PBMoves::ERUPTION||
          move.id == PBMoves::AVALANCHE)
          basedamage=(basedamage*1.5).round
        end
      when 28 # Snowy Mountain
        if (move.id == PBMoves::VITALTHROW || move.id == PBMoves::CIRCLETHROW ||
          move.id == PBMoves::STORMTHROW)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::OMINOUSWIND ||
          move.id == PBMoves::SILVERWIND || move.id == PBMoves::TWISTER ||
          move.id == PBMoves::RAZORWIND || move.id == PBMoves::FAIRYWIND)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::ICYWIND)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::OMINOUSWIND || move.id == PBMoves::ICYWIND ||
          move.id == PBMoves::SILVERWIND || move.id == PBMoves::TWISTER ||
          move.id == PBMoves::RAZORWIND || move.id == PBMoves::FAIRYWIND ||
          move.id == PBMoves::GUST) && pbWeather==PBWeather::STRONGWINDS
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::SCALD || move.id == PBMoves::STEAMERUPTION)
          basedamage=(basedamage*0.5).round
        end
        if (move.id == PBMoves::AVALANCHE || move.id == PBMoves::POWDERSNOW)
          basedamage=(basedamage*1.5).round
        end
      when 29 # Holy
        if (move.id == PBMoves::MYSTICALFIRE || move.id == PBMoves::MAGICALLEAF ||
          move.id == PBMoves::ANCIENTPOWER)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::JUDGMENT || move.id == PBMoves::SACREDFIRE)
          basedamage=(basedamage*1.2).round
        end
        if (move.id == PBMoves::PSYSTRIKE || move.id == PBMoves::AEROBLAST ||
          move.id == PBMoves::SACREDFIRE || move.id == PBMoves::ORIGINPULSE ||
          move.id == PBMoves::DOOMDUMMY || move.id == PBMoves::JUDGMENT ||
          move.id == PBMoves::MISTBALL || move.id == PBMoves::CRUSHGRIP ||
          move.id == PBMoves::LUSTERPURGE || move.id == PBMoves::SECRETSWORD ||
          move.id == PBMoves::PSYCHOBOOST || move.id == PBMoves::RELICSONG ||
          move.id == PBMoves::SPACIALREND || move.id == PBMoves::HYPERSPACEHOLE ||
          move.id == PBMoves::ROAROFTIME || move.id == PBMoves::LANDSWRATH ||
          move.id == PBMoves::PRECIPICEBLADES || move.id == PBMoves::DRAGONASCENT ||
          move.id == PBMoves::MOONGEISTBEAM || move.id == PBMoves::SUNSTEELSTRIKE ||
          move.id == PBMoves::PRISMATICLASER || move.id == PBMoves::FLEURCANNON ||
          move.id == PBMoves::DIAMONDSTORM )
          basedamage=(basedamage*1.3).round
        end
      when 30 # Mirror
        if (move.id == PBMoves::MIRRORSHOT)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::CHARGEBEAM || move.id == PBMoves::SOLARBEAM ||
          move.id == PBMoves::PSYBEAM || move.id == PBMoves::TRIATTACK ||
          move.id == PBMoves::BUBBLEBEAM || move.id == PBMoves::HYPERBEAM ||
          move.id == PBMoves::ICEBEAM || move.id == PBMoves::ORIGINPULSE ||
          move.id == PBMoves::MOONGEISTBEAM || move.id == PBMoves::FLEURCANNON) && $fecounter ==1
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::AURORABEAM || move.id == PBMoves::SIGNALBEAM ||
          move.id == PBMoves::FLASHCANNON || move.id == PBMoves::LUSTERPURGE ||
          move.id == PBMoves::DAZZLINGGLEAM || move.id == PBMoves::TECHNOBLAST ||
          move.id == PBMoves::DOOMDUMMY || move.id == PBMoves::PRISMATICLASER ||
          move.id == PBMoves::PHOTONGEYSER)
          basedamage=(basedamage*1.5).round
        end
        $fecounter = 0
      when 31 # Fairy Tale
        if (move.id == PBMoves::DRAININGKISS)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::NIGHTSLASH || move.id == PBMoves::LEAFBLADE || move.id == PBMoves::PSYCHOCUT ||
          move.id == PBMoves::SMARTSTRIKE || move.id == PBMoves::AIRSLASH || move.id == PBMoves::SOLARBLADE)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::MAGICALLEAF || move.id == PBMoves::MYSTICALFIRE ||
          move.id == PBMoves::ANCIENTPOWER || move.id == PBMoves::RELICSONG ||
          move.id == PBMoves::SPARKLINGARIA || move.id == PBMoves::MOONGEISTBEAM ||
          move.id == PBMoves::FLEURCANNON)
          basedamage=(basedamage*1.5).round
        end
      when 32 # Dragon's Den
        if (move.id == PBMoves::MEGAKICK)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::SMACKDOWN || move.id == PBMoves::THOUSANDARROWS)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::MAGMASTORM || move.id == PBMoves::LAVAPLUME)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::DRAGONASCENT)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::PAYDAY)
          basedamage=(basedamage*2).round
        end
      when 33 # Flower Garden
        if (move.id == PBMoves::CUT) && $fecounter > 0
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::PETALBLIZZARD || move.id == PBMoves::PETALDANCE || move.id == PBMoves::FLEURCANNON) && $fecounter == 2
          basedamage=(basedamage*1.2).round
        end
        if (move.id == PBMoves::PETALBLIZZARD || move.id == PBMoves::PETALDANCE || move.id == PBMoves::FLEURCANNON) && $fecounter > 2
          basedamage=(basedamage*1.5).round
        end
      when 34 # Starlight Arena
        if (move.id == PBMoves::AURORABEAM || move.id == PBMoves::SIGNALBEAM ||
          move.id == PBMoves::FLASHCANNON || move.id == PBMoves::LUSTERPURGE ||
          move.id == PBMoves::DAZZLINGGLEAM || move.id == PBMoves::MIRRORSHOT ||
          move.id == PBMoves::TECHNOBLAST || move.id == PBMoves::SOLARBEAM ||
          move.id == PBMoves::PHOTONGEYSER)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::MOONBLAST)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::DRACOMETEOR || move.id == PBMoves::METEORMASH ||
          move.id == PBMoves::COMETPUNCH || move.id == PBMoves::SPACIALREND ||
          move.id == PBMoves::SWIFT || move.id == PBMoves::HYPERSPACEHOLE ||
          move.id == PBMoves::HYPERSPACEFURY || move.id == PBMoves::MOONGEISTBEAM ||
          move.id == PBMoves::SUNSTEELSTRIKE)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::DOOMDUMMY)
          basedamage=(basedamage*4).round
        end
      when 35 # New World
        if (move.id == PBMoves::AURORABEAM || move.id == PBMoves::SIGNALBEAM ||
          move.id == PBMoves::FLASHCANNON || move.id == PBMoves::DAZZLINGGLEAM ||
          move.id == PBMoves::MIRRORSHOT && move.id == PBMoves::PHOTONGEYSER)
          basedamage=(basedamage*1.5).round
        end
         if (move.id == PBMoves::EARTHQUAKE || move.id == PBMoves::MAGNITUDE ||
         move.id == PBMoves::BULLDOZE)
          basedamage=(basedamage*0.25).round
        end
        if (move.id == PBMoves::EARTHPOWER || move.id == PBMoves::POWERGEM ||
          move.id == PBMoves::ERUPTION)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::PSYSTRIKE || move.id == PBMoves::AEROBLAST ||
          move.id == PBMoves::SACREDFIRE || move.id == PBMoves::MISTBALL ||
          move.id == PBMoves::LUSTERPURGE || move.id == PBMoves::ORIGINPULSE ||
          move.id == PBMoves::PRECIPICEBLADES || move.id == PBMoves::DRAGONASCENT ||
          move.id == PBMoves::PSYCHOBOOST || move.id == PBMoves::ROAROFTIME ||
          move.id == PBMoves::MAGMASTORM || move.id == PBMoves::CRUSHGRIP ||
          move.id == PBMoves::JUDGMENT || move.id == PBMoves::SEEDFLARE ||
          move.id == PBMoves::SHADOWFORCE || move.id == PBMoves::SEARINGSHOT ||
          move.id == PBMoves::VCREATE || move.id == PBMoves::SECRETSWORD ||
          move.id == PBMoves::SACREDSWORD || move.id == PBMoves::RELICSONG ||
          move.id == PBMoves::FUSIONBOLT || move.id == PBMoves::FUSIONFLARE ||
          move.id == PBMoves::ICEBURN || move.id == PBMoves::FREEZESHOCK ||
          move.id == PBMoves::BOLTSTRIKE || move.id == PBMoves::BLUEFLARE ||
          move.id == PBMoves::TECHNOBLAST || move.id == PBMoves::OBLIVIONWING ||
          move.id == PBMoves::LANDSWRATH || move.id == PBMoves::THOUSANDARROWS ||
          move.id == PBMoves::THOUSANDWAVES || move.id == PBMoves::DIAMONDSTORM ||
          move.id == PBMoves::STEAMERUPTION || move.id == PBMoves::COREENFORCER ||
          move.id == PBMoves::FLEURCANNON || move.id == PBMoves::PRISMATICLASER ||
          move.id == PBMoves::SUNSTEELSTRIKE || move.id == PBMoves::SPECTRALTHIEF ||
          move.id == PBMoves::MOONGEISTBEAM || move.id == PBMoves::MULTIATTACK ||
          move.id == PBMoves::MINDBLOWN || move.id == PBMoves::PLASMAFISTS)
          basedamage=(basedamage*1.5).round
        end
        if (move.id == PBMoves::VACUUMWAVE || move.id == PBMoves::DRACOMETEOR ||
          move.id == PBMoves::METEORMASH || move.id == PBMoves::MOONBLAST ||
          move.id == PBMoves::COMETPUNCH || move.id == PBMoves::SWIFT ||
          move.id == PBMoves::HYPERSPACEHOLE || move.id == PBMoves::SPACIALREND ||
          move.id == PBMoves::HYPERSPACEFURY|| move.id == PBMoves::ANCIENTPOWER ||
          move.id == PBMoves::FUTUREDUMMY)
          basedamage=(basedamage*2).round
        end
        if (move.id == PBMoves::DOOMDUMMY)
          basedamage=(basedamage*4).round
        end
      when 37 # Psychic Terrain
          if (move.id == PBMoves::HEX || move.id == PBMoves::MAGICALLEAF ||
            move.id == PBMoves::MYSTICALFIRE || move.id == PBMoves::MOONBLAST ||
            move.id == PBMoves::AURASPHERE || move.id == PBMoves::MINDBLOWN)
            basedamage=(basedamage*1.5).round
          end
      end
    end

    #Glitch field attack power adjustment
    if skill>=PBTrainerAI.highSkill
      if $fefieldeffect == 24 && type>=0 && move.pbIsSpecial?(type)
        if (attitemworks && attacker.item == PBItems::ASSAULTVEST)
          if gl1 < gl2
            atk=(atk*1.5).round
          end
        end
        if (attitemworks && attacker.item == PBItems::EVIOLITE) &&
          pbGetEvolvedFormData(attacker.species).length>0
          if gl1 < gl2
            atk=(atk*1.5).round
          end
        end
        if (attitemworks && attacker.item == PBItems::DEEPSEASCALE) &&
          (attacker.species == PBSpecies::CLAMPERL)
          if gl1 < gl2
            atk=(atk*2).round
          end
        end
        if (attitemworks && attacker.item == PBItems::METALPOWDER) &&
          (attacker.species == PBSpecies::DITTO)
          if gl1 < gl2
            atk=(atk*1.5).round
          end
        end
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::FLOWERGIFT) && pbWeather==PBWeather::SUNNYDAY
          if gl1 < gl2
            atk=(atk*1.5).round
          end
        end
      end
    end

    if skill>=PBTrainerAI.mediumSkill
      ############ ATTACKER ABILITY CHECKS ############
      if !attacker.abilitynulled
        #Technician
        if attacker.ability == PBAbilities::TECHNICIAN
          if (basedamage<=60) || ($fefieldeffect == 17 && basedamage<=80)
            basedamage=(basedamage*1.5).round
          end
        # Iron Fist
        elsif attacker.ability == PBAbilities::IRONFIST
          if move.isPunchingMove?
            basedamage=(basedamage*1.2).round
          end
        # Strong Jaw
        elsif attacker.ability == PBAbilities::STRONGJAW
          if (move.id == PBMoves::BITE || move.id == PBMoves::CRUNCH ||
            move.id == PBMoves::THUNDERFANG || move.id == PBMoves::FIREFANG ||
            move.id == PBMoves::ICEFANG || move.id == PBMoves::POISONFANG ||
            move.id == PBMoves::HYPERFANG || move.id == PBMoves::PSYCHICFANGS)
            basedamage=(basedamage*1.5).round
          end
        #Tough Claws
        elsif attacker.ability == PBAbilities::TOUGHCLAWS
          if move.isContactMove?
            basedamage=(basedamage*1.3).round
          end
        # Reckless
        elsif attacker.ability == PBAbilities::RECKLESS
          if @function==0xFA ||  # Take Down, etc.
              @function==0xFB ||  # Double-Edge, etc.
              @function==0xFC ||  # Head Smash
              @function==0xFD ||  # Volt Tackle
              @function==0xFE ||  # Flare Blitz
              @function==0x10B || # Jump Kick, Hi Jump Kick
              @function==0x130    # Shadow End
            basedamage=(basedamage*1.2).round
          end
        # Flare Boost
        elsif attacker.ability == PBAbilities::FLAREBOOST
          if (attacker.status==PBStatuses::BURN || $fefieldeffect == 7) && move.pbIsSpecial?(type)
            basedamage=(basedamage*1.5).round
          end
        # Toxic Boost
        elsif attacker.ability == PBAbilities::TOXICBOOST
          if (attacker.status==PBStatuses::POISON ||
          $fefieldeffect == 10 || $fefieldeffect == 11 ||
          $fefieldeffect == 19 || $fefieldeffect == 26) && move.pbIsPhysical?(type)
            basedamage=(basedamage*1.5).round
          end
        # Rivalry
        elsif attacker.ability == PBAbilities::RIVALRY
          if attacker.gender!=2 && opponent.gender!=2
            if attacker.gender==opponent.gender
              basedamage=(basedamage*1.25).round
            else
              basedamage=(basedamage*0.75).round
            end
          end
        # Sand Force
        elsif attacker.ability == PBAbilities::SANDFORCE
          if pbWeather==PBWeather::SANDSTORM && (type == PBTypes::ROCK ||
            (type == PBTypes::GROUND) || type == PBTypes::STEEL)
            basedamage=(basedamage*1.3).round
          end
        # Analytic
        elsif attacker.ability == PBAbilities::ANALYTIC
          if opponent.hasMovedThisRound?
            basedamage = (basedamage*1.3).round
          end
        # Sheer Force
        elsif attacker.ability == PBAbilities::SHEERFORCE
          if move.addlEffect>0
            basedamage=(basedamage*1.3).round
          end
        # Normalize
        elsif attacker.ability == PBAbilities::NORMALIZE
          type=PBTypes::NORMAL
          basedamage=(basedamage*1.2).round
        # Hustle
        elsif attacker.ability == PBAbilities::HUSTLE
          if move.pbIsPhysical?(type)
            atk=(atk*1.5).round
          end
        # Guts
        elsif attacker.ability == PBAbilities::GUTS
          if attacker.status!=0 && move.pbIsPhysical?(type)
          atk=(atk*1.5).round
          end
        #Plus/Minus
        elsif attacker.ability == PBAbilities::PLUS ||  attacker.ability == PBAbilities::MINUS
          if move.pbIsSpecial?(type)
            partner=attacker.pbPartner
            if (!partner.abilitynulled && partner.ability == PBAbilities::PLUS) || (!partner.abilitynulled && partner.ability == PBAbilities::MINUS)
              atk=(atk*1.5).round
            elsif $fefieldeffect == 18 && skill>=PBTrainerAI.bestSkill
              atk=(atk*1.5).round
            end
          end
        #Defeatist
        elsif attacker.ability == PBAbilities::DEFEATIST
          if attacker.hp<=(attacker.totalhp/2.0).floor
            atk=(atk*0.5).round
          end
        #Pure/Huge Power
        elsif attacker.ability == PBAbilities::PUREPOWER || attacker.ability == PBAbilities::HUGEPOWER
          if skill>=PBTrainerAI.bestSkill
            if attacker.ability == PBAbilities::PUREPOWER && $fefieldeffect==37
              if move.pbIsSpecial?(type)
                atk=(atk*2.0).round
              end
            else
              if move.pbIsPhysical?(type)
                atk=(atk*2.0).round
              end
            end
          elsif move.pbIsPhysical?(type)
            atk=(atk*2.0).round
          end
        #Solar Power
        elsif attacker.ability == PBAbilities::SOLARPOWER
          if pbWeather==PBWeather::SUNNYDAY && move.pbIsSpecial?(type)
            atk=(atk*1.5).round
          end
        #Flash Fire
        elsif attacker.ability == PBAbilities::FLASHFIRE
          if attacker.effects[PBEffects::FlashFire] && type == PBTypes::FIRE
            atk=(atk*1.5).round
          end
        #Slow Start
        elsif attacker.ability == PBAbilities::SLOWSTART
          if attacker.turncount<5 && move.pbIsPhysical?(type)
            atk=(atk*0.5).round
          end
        # Type Changing Abilities
        elsif type == PBTypes::NORMAL && attacker.ability != PBAbilities::NORMALIZE
          # Aerilate
          if attacker.ability == PBAbilities::AERILATE
            type=PBTypes::FLYING
            basedamage=(basedamage*1.2).round
          # Galvanize
          elsif attacker.ability == PBAbilities::GALVANIZE
            type=PBTypes::ELECTRIC
            if skill>=PBTrainerAI.bestSkill
              if $fefieldeffect == 1 || $fefieldeffect == 17 # Electric or Factory Fields
                basedamage=(basedamage*1.5).round
              elsif $fefieldeffect == 18 # Short-Circuit Field
                basedamage=(basedamage*2).round
              else
                basedamage=(basedamage*1.2).round
              end
            else
              basedamage=(basedamage*1.2).round
            end
          # Pixilate
          elsif attacker.ability == PBAbilities::PIXILATE
            if skill>=PBTrainerAI.bestSkill
              type=PBTypes::FAIRY unless $fefieldeffect == 24
              if $fefieldeffect == 3 # Misty Field
                basedamage=(basedamage*1.5).round
              else
                basedamage=(basedamage*1.2).round
              end
            else
              type=PBTypes::FAIRY
              basedamage=(basedamage*1.2).round
            end
          # Refrigerate
          elsif attacker.ability == PBAbilities::REFRIGERATE
            type=PBTypes::ICE
            if skill>=PBTrainerAI.bestSkill
              if $fefieldeffect == 13 || $fefieldeffect == 28 # Icy Fields
                basedamage=(basedamage*1.5).round
              else
                basedamage=(basedamage*1.2).round
              end
            else
              basedamage=(basedamage*1.2).round
            end
          end
        end
      end

      ############ OPPONENT ABILITY CHECKS ############
      if !opponent.abilitynulled && !(opponent.moldbroken)
        # Heatproof
        if opponent.ability == PBAbilities::HEATPROOF
          if type == PBTypes::FIRE
            basedamage=(basedamage*0.5).round
          end
        # Dry Skin
        elsif opponent.ability == PBAbilities::DRYSKIN
          if type == PBTypes::FIRE
            basedamage=(basedamage*1.25).round
          end
        elsif opponent.ability == PBAbilities::THICKFAT
          if type == PBTypes::ICE || type == PBTypes::FIRE
           atk=(atk*0.5).round
          end
        end
      end

      ############ ATTACKER ITEM CHECKS ############
      if attitemworks #don't bother with this if it doesn't work
        #Type-boosting items
        case type
        when 0
          if attacker.item == PBItems::SILKSCARF
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::NORMALGEM
            basedamage=(basedamage*1.3).round
          end
        when 1
          if (attacker.item == PBItems::BLACKBELT || attacker.item == PBItems::FISTPLATE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::FIGHTINGGEM
            basedamage=(basedamage*1.3).round
          end
        when 2
          if (attacker.item == PBItems::SHARPBEAK || attacker.item == PBItems::SKYPLATE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::FLYINGGEM
            basedamage=(basedamage*1.3).round
          end
        when 3
          if (attacker.item == PBItems::POISONBARB || attacker.item == PBItems::TOXICPLATE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::POISONGEM
            basedamage=(basedamage*1.3).round
          end
        when 4
          if (attacker.item == PBItems::SOFTSAND || attacker.item == PBItems::EARTHPLATE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::GROUNDGEM
            basedamage=(basedamage*1.3).round
          end
        when 5
          if (attacker.item == PBItems::HARDSTONE || attacker.item == PBItems::STONEPLATE || attacker.item == PBItems::ROCKINCENSE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::ROCKGEM
            basedamage=(basedamage*1.3).round
          end
        when 6
          if (attacker.item == PBItems::SILVERPOWDER || attacker.item == PBItems::INSECTPLATE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::BUGGEM
            basedamage=(basedamage*1.3).round
          end
        when 7
          if (attacker.item == PBItems::SPELLTAG || attacker.item == PBItems::SPOOKYPLATE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::GHOSTGEM
            basedamage=(basedamage*1.3).round
          end
        when 8
          if (attacker.item == PBItems::METALCOAT || attacker.item == PBItems::IRONPLATE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::STEELGEM
            basedamage=(basedamage*1.3).round
          end
        when 9 #?????
        when 10
          if (attacker.item == PBItems::CHARCOAL || attacker.item == PBItems::FLAMEPLATE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::FIREGEM
            basedamage=(basedamage*1.3).round
          end
        when 11
          if (attacker.item == PBItems::MYSTICWATER || attacker.item == PBItems::SPLASHPLATE ||
              attacker.item == PBItems::SEAINCENSE || attacker.item == PBItems::WAVEINCENSE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::WATERGEM
            basedamage=(basedamage*1.3).round
          end
        when 12
          if (attacker.item == PBItems::MIRACLESEED || attacker.item == PBItems::MEADOWPLATE || attacker.item == PBItems::ROSEINCENSE) #it me
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::GRASSGEM
            basedamage=(basedamage*1.3).round
          end
        when 13
          if (attacker.item == PBItems::MAGNET || attacker.item == PBItems::ZAPPLATE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::ELECTRICGEM
            basedamage=(basedamage*1.3).round
          end
        when 14
          if (attacker.item == PBItems::TWISTEDSPOON || attacker.item == PBItems::MINDPLATE || attacker.item == PBItems::ODDINCENSE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::PSYCHICGEM
            basedamage=(basedamage*1.3).round
          end
        when 15
          if (attacker.item == PBItems::NEVERMELTICE || attacker.item == PBItems::ICICLEPLATE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::ICEGEM
            basedamage=(basedamage*1.3).round
          end
        when 16
          if (attacker.item == PBItems::DRAGONFANG || attacker.item == PBItems::DRACOPLATE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::DRAGONGEM
            basedamage=(basedamage*1.3).round
          end
        when 17
          if (attacker.item == PBItems::BLACKGLASSES || attacker.item == PBItems::DREADPLATE)
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::DARKGEM
            basedamage=(basedamage*1.3).round
          end
        when 18
          if attacker.item == PBItems::PIXIEPLATE
            basedamage=(basedamage*1.2).round
          elsif attacker.item == PBItems::FAIRYGEM
            basedamage=(basedamage*1.3).round
          end
        end
        # Muscle Band
        if attacker.item == PBItems::MUSCLEBAND && move.pbIsPhysical?(type)
          basedamage=(basedamage*1.1).round
        # Wise Glasses
        elsif attacker.item == PBItems::WISEGLASSES && move.pbIsSpecial?(type)
          basedamage=(basedamage*1.1).round
        # Legendary Orbs
        elsif attacker.item == PBItems::LUSTROUSORB
          if (attacker.species == PBSpecies::PALKIA) && (type == PBTypes::DRAGON || type == PBTypes::WATER)
            basedamage=(basedamage*1.2).round
          end
        elsif attacker.item == PBItems::ADAMANTORB
          if (attacker.species == PBSpecies::DIALGA) && (type == PBTypes::DRAGON || type == PBTypes::STEEL)
            basedamage=(basedamage*1.2).round
          end
        elsif attacker.item == PBItems::GRISEOUSORB
          if (attacker.species == PBSpecies::GIRATINA) && (type == PBTypes::DRAGON || type == PBTypes::GHOST)
            basedamage=(basedamage*1.2).round
          end
        elsif attacker.item == PBItems::SOULDEW
          if (attacker.species == PBSpecies::LATIAS) || (attacker.species == PBSpecies::LATIOS) &&
            (type == PBTypes::DRAGON || type == PBTypes::PSYCHIC)
            basedamage=(basedamage*1.2).round
          end
        end
      end

      ############ MISC CHECKS ############
      # Charge
      if attacker.effects[PBEffects::Charge]>0 && type == PBTypes::ELECTRIC
        basedamage=(basedamage*2.0).round
      end
      # Helping Hand
      if attacker.effects[PBEffects::HelpingHand]
        basedamage=(basedamage*1.5).round
      end
      # Water/Mud Sport
      if type == PBTypes::FIRE
        if @field.effects[PBEffects::WaterSport]>0
          basedamage=(basedamage*0.33).round
        end
      elsif type == PBTypes::ELECTRIC
        if @field.effects[PBEffects::MudSport]>0
          basedamage=(basedamage*0.33).round
        end
      # Dark Aura/Aurabreak
      elsif type == PBTypes::DARK
        for i in @battlers
          if i.ability == PBAbilities::DARKAURA
            breakaura=0
            for j in @battlers
              if j.ability == PBAbilities::AURABREAK
                breakaura+=1
              end
            end
            if breakaura!=0
              basedamage=(basedamage*2/3).round
            else
              basedamage=(basedamage*1.33).round
            end
          end
        end
      # Fairy Aura/Aurabreak
      elsif type == PBTypes::FAIRY
        for i in @battlers
          if i.ability == PBAbilities::FAIRYAURA
            breakaura=0
            for j in @battlers
              if j.ability == PBAbilities::AURABREAK
                breakaura+=1
              end
            end
            if breakaura!=0
              basedamage=(basedamage*2/3).round
            else
              basedamage=(basedamage*1.3).round
            end
          end
        end
      end
      #Battery
      if (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::BATTERY) && move.pbIsSpecial?(type)
        atk=(atk*1.3).round
      end
      #Flower Gift
      if pbWeather==PBWeather::SUNNYDAY && move.pbIsPhysical?(type)
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::FLOWERGIFT) &&
           (attacker.species == PBSpecies::CHERRIM)
          atk=(atk*1.5).round
        end
        if (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::FLOWERGIFT) &&
           attacker.pbPartner.species == PBSpecies::CHERRIM
          atk=(atk*1.5).round
        end
      end
    end

    # Pinch Abilities
    if !attacker.abilitynulled
      if skill>=PBTrainerAI.bestSkill
        if $fefieldeffect == 7 && attacker.ability == PBAbilities::BLAZE && type == PBTypes::FIRE
          atk=(atk*1.5).round
        elsif $fefieldeffect == 15 && attacker.ability == PBAbilities::OVERGROW && type == PBTypes::GRASS
          atk=(atk*1.5).round
        elsif $fefieldeffect == 15 && attacker.ability == PBAbilities::SWARM && type == PBTypes::BUG
          atk=(atk*1.5).round
        elsif ($fefieldeffect == 21 || $fefieldeffect == 22) && attacker.ability == PBAbilities::TORRENT && type == PBTypes::WATER
          atk=(atk*1.5).round
        elsif $fefieldeffect == 33 && attacker.ability == PBAbilities::SWARM && type == PBTypes::BUG
          atk=(atk*1.5).round if $fecounter == 0 || $fecounter == 1
          atk=(atk*2).round if $fecounter == 2 || $fecounter == 3
          atk=(atk*3).round if $fecounter == 4
        elsif $fefieldeffect == 33 && attacker.ability == PBAbilities::OVERGROW && type == PBTypes::GRASS
          case $fecounter
          when 1
            if attacker.hp<=(attacker.totalhp*0.67).floor
              atk=(atk*1.5).round
            end
          when 2
              atk=(atk*1.5).round
          when 3
              atk=(atk*2).round
          when 4
              atk=(atk*3).round
          end
        else
          if attacker.ability == PBAbilities::OVERGROW
            if attacker.hp<=(attacker.totalhp/3.0).floor || type == PBTypes::GRASS
              atk=(atk*1.5).round
            end
          elsif attacker.ability == PBAbilities::BLAZE
            if attacker.hp<=(attacker.totalhp/3.0).floor || type == PBTypes::FIRE
              atk=(atk*1.5).round
            end
          elsif attacker.ability == PBAbilities::TORRENT
            if attacker.hp<=(attacker.totalhp/3.0).floor || type == PBTypes::WATER
              atk=(atk*1.5).round
            end
          elsif attacker.ability == PBAbilities::SWARM
            if attacker.hp<=(attacker.totalhp/3.0).floor || type == PBTypes::BUG
              atk=(atk*1.5).round
            end
          end
        end
      elsif skill>=PBTrainerAI.mediumSkill
        if attacker.ability == PBAbilities::OVERGROW
          if attacker.hp<=(attacker.totalhp/3.0).floor || type == PBTypes::GRASS
            atk=(atk*1.5).round
          end
        elsif attacker.ability == PBAbilities::BLAZE
          if attacker.hp<=(attacker.totalhp/3.0).floor || type == PBTypes::FIRE
            atk=(atk*1.5).round
          end
        elsif attacker.ability == PBAbilities::TORRENT
          if attacker.hp<=(attacker.totalhp/3.0).floor || type == PBTypes::WATER
            atk=(atk*1.5).round
          end
        elsif attacker.ability == PBAbilities::SWARM
          if attacker.hp<=(attacker.totalhp/3.0).floor || type == PBTypes::BUG
            atk=(atk*1.5).round
          end
        end
      end
    end

    # Attack-boosting items
    if skill>=PBTrainerAI.highSkill
      if (attitemworks && attacker.item == PBItems::THICKCLUB)
        if ((attacker.species == PBSpecies::CUBONE) || (attacker.species == PBSpecies::MAROWAK)) && move.pbIsPhysical?(type)
          atk=(atk*2.0).round
        end
      elsif (attitemworks && attacker.item == PBItems::DEEPSEATOOTH)
        if (attacker.species == PBSpecies::CLAMPERL) && move.pbIsSpecial?(type)
          atk=(atk*2.0).round
        end
      elsif (attitemworks && attacker.item == PBItems::LIGHTBALL)
        if (attacker.species == PBSpecies::PIKACHU)
          atk=(atk*2.0).round
        end
      elsif (attitemworks && attacker.item == PBItems::CHOICEBAND) && move.pbIsPhysical?(type)
        atk=(atk*1.5).round
      elsif (attitemworks && attacker.item == PBItems::CHOICESPECS) && move.pbIsSpecial?(type)
        atk=(atk*1.5).round
      end
    end

    #Specific ability field boosts
    if skill>=PBTrainerAI.bestSkill
      if $fefieldeffect == 34 || $fefieldeffect == 35
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::VICTORYSTAR)
          atk=(atk*1.5).round
        end
        partner=attacker.pbPartner
        if partner && (!partner.abilitynulled && partner.ability == PBAbilities::VICTORYSTAR)
          atk=(atk*1.5).round
        end
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::QUEENLYMAJESTY) &&
        ($fefieldeffect==5 || $fefieldeffect==31)
       atk=(atk*1.5).round
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::LONGREACH) &&
        ($fefieldeffect==27 || $fefieldeffect==28)
        atk=(atk*1.5).round
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::CORROSION) &&
        ($fefieldeffect==10 || $fefieldeffect==11)
        atk=(atk*1.5).round
      end
    end

    # Get base defense stat
    defense=pbRoughStat(opponent,PBStats::DEFENSE,skill)
    applysandstorm=false
    if type>=0 && move.pbIsSpecial?(type)
      if move.function!=0x122 # Psyshock
        defense=pbRoughStat(opponent,PBStats::SPDEF,skill)
        if $fefieldeffect == 24
          gl1 = pbRoughStat(opponent,PBStats::SPATK,skill)
          gl2 = pbRoughStat(opponent,PBStats::SPDEF,skill)
          gl3 = opponent.stages[PBStats::SPDEF]+6
          gl4 = opponent.stages[PBStats::SPATK]+6
          if oppitemworks
            gl2 *= 1.5 if opponent.item == PBItems::ASSAULTVEST
            gl1 *= 1.5 if opponent.item == PBItems::CHOICESPECS
            gl2 *= 1.5 if opponent.item == PBItems::EVIOLITE && pbGetEvolvedFormData(opponent.species).length>0
            gl1 *= 2 if opponent.item == PBItems::DEEPSEATOOTH && opponent.species == PBSpecies::CLAMPERL
            gl1 *= 2 if opponent.item == PBItems::LIGHTBALL && opponent.species == PBSpecies::PIKACHU
            gl2 *= 2 if opponent.item == PBItems::DEEPSEASCALE && opponent.species == PBSpecies::CLAMPERL
            gl2 *= 1.5 if opponent.item == PBItems::METALPOWDER && opponent.species == PBSpecies::DITTO
          end
          if !opponent.abilitynulled
            gl1 *= 1.5 if opponent.ability == PBAbilities::FLAREBOOST && opponent.status==PBStatuses::BURN
            gl1 *= 1.5 if opponent.ability == PBAbilities::MINUS && (!opponent.pbPartner.abilitynulled && opponent.pbPartner.ability == PBAbilities::PLUS)
            gl1 *= 1.5 if opponent.ability == PBAbilities::PLUS && (!opponent.pbPartner.abilitynulled && opponent.pbPartner.ability == PBAbilities::MINUS)
            gl1 *= 1.5 if opponent.ability == PBAbilities::SOLARPOWER && pbWeather==PBWeather::SUNNYDAY
            gl2 *= 1.5 if opponent.ability == PBAbilities::FLOWERGIFT && pbWeather==PBWeather::SUNNYDAY
          end
          gl1 *= 1.3 if (!opponent.pbPartner.abilitynulled && opponent.pbPartner.ability == PBAbilities::BATTERY)
          gl1=(gl1*stagemul[gl4]/stagediv[gl4]).floor
          gl2=(gl2*stagemul[gl3]/stagediv[gl3]).floor
          if gl1 > gl2
            defense=pbRoughStat(opponent,PBStats::SPATK,skill)
          end
        end
        applysandstorm=true
      end
    end
    if opponent.effects[PBEffects::PowerTrick]
      defense=pbRoughStat(opponent,PBStats::ATTACK,skill)
    end
    defense = 1 if (defense == 0 || !defense)

    #Glitch Item Checks
    if skill>=PBTrainerAI.highSkill && $fefieldeffect == 24
      if type>=0 && move.pbIsSpecial?(type) && move.function!=0x122
        # Glitch Specs
        if (oppitemworks && opponent.item == PBItems::CHOICESPECS)
          if gl1 > gl2
            defense=(defense*1.5).round
          end
        # Glitchsea Tooth
        elsif (oppitemworks && opponent.item == PBItems::DEEPSEATOOTH) && (opponent.species == PBSpecies::CLAMPERL)
          if gl1 > gl2
            defense=(defense*2).round
          end
        elsif (oppitemworks && opponent.item == PBItems::LIGHTBALL) && (opponent.species == PBSpecies::PIKACHU)
          if gl1 > gl2
            defense=(defense*2).round
          end
        end
      end
    end

    if skill>=PBTrainerAI.mediumSkill
      # Sandstorm weather
      if pbWeather==PBWeather::SANDSTORM
        if opponent.pbHasType?(:ROCK) && applysandstorm
          defense=(defense*1.5).round
        end
      end
      # Defensive Abilities
      if !opponent.abilitynulled
        if opponent.ability == PBAbilities::MARVELSCALE
          if move.pbIsPhysical?(type)
            if opponent.status>0
              defense=(defense*1.5).round
            elsif ($fefieldeffect == 3 || $fefieldeffect == 9 ||
              $fefieldeffect == 31 || $fefieldeffect == 32 || $fefieldeffect == 34) &&
              skill>=PBTrainerAI.bestSkill
              defense=(defense*1.5).round
            end
          end
        elsif opponent.ability == PBAbilities::GRASSPELT
          if move.pbIsPhysical?(type) && ($fefieldeffect == 2 || $fefieldeffect == 15) # Grassy Field
            defense=(defense*1.5).round
          end
        elsif opponent.ability == PBAbilities::FLUFFY && !(opponent.moldbroken)
          if move.isContactMove? && !(!attacker.abilitynulled && attacker.ability == PBAbilities::LONGREACH)
            defense=(defense*2).round
          end
          if type == PBTypes::FIRE
            defense=(defense*0.5).round
          end
        elsif opponent.ability == PBAbilities::FURCOAT
          if move.pbIsPhysical?(type) && !(opponent.moldbroken)
            defense=(defense*2).round
          end
        end
      end
      if (pbWeather==PBWeather::SUNNYDAY || $fefieldeffect == 33) && move.pbIsSpecial?(type)
        if (!opponent.abilitynulled && opponent.ability == PBAbilities::FLOWERGIFT) &&
           (opponent.species == PBSpecies::CHERRIM)
          defense=(defense*1.5).round
        end
        if (!opponent.pbPartner.abilitynulled && opponent.pbPartner.ability == PBAbilities::FLOWERGIFT) && opponent.pbPartner.species == PBSpecies::CHERRIM
          defense=(defense*1.5).round
        end
      end
    end

    # Various field boosts
    if skill>=PBTrainerAI.bestSkill
      if $fefieldeffect == 3 && move.pbIsSpecial?(type) && opponent.pbHasType?(:FAIRY)
        defense=(defense*1.5).round
      end
      if $fefieldeffect == 12 && move.pbIsSpecial?(type) && opponent.pbHasType?(:GROUND)
        defense=(defense*1.5).round
      end
      if $fefieldeffect == 22 && move.pbIsPhysical?(type) && !type == PBTypes::WATER
        defense=(defense*1.5).round
      end
    end

    # Defense-boosting items
    if skill>=PBTrainerAI.highSkill
      if (oppitemworks && opponent.item == PBItems::EVIOLITE)
        evos=pbGetEvolvedFormData(opponent.species)
        if evos && evos.length>0
          defense=(defense*1.5).round
        end
      elsif (oppitemworks && opponent.item == PBItems::ASSAULTVEST)
        if move.pbIsSpecial?(type)
          defense=(defense*1.5).round
        end
      elsif (oppitemworks && opponent.item == PBItems::DEEPSEASCALE)
        if (opponent.species == PBSpecies::CLAMPERL) && move.pbIsSpecial?(type)
          defense=(defense*2.0).round
        end
      elsif (oppitemworks && opponent.item == PBItems::METALPOWDER)
        if (opponent.species == PBSpecies::DITTO) && !opponent.effects[PBEffects::Transform] && move.pbIsPhysical?(type)
          defense=(defense*2.0).round
        end
      end
    end

    # Prism Armor & Shadow Shield
    if skill>=PBTrainerAI.bestSkill
      if ((!attacker.abilitynulled && attacker.ability == PBAbilities::PRISMARMOR) ||
        (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWSHIELD)) && $fefieldeffect==4
        defense=(defense*2.0).round
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::PRISMARMOR) && ($fefieldeffect==9 || $fefieldeffect==25)
        defense=(defense*2.0).round
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWSHIELD) && ($fefieldeffect==34 || $fefieldeffect==35)
        defense=(defense*2.0).round
      end
    end

    # Main damage calculation
    damage=(((2.0*attacker.level/5+2).floor*basedamage*atk/defense).floor/50).floor+2 if basedamage >= 0
    # Multi-targeting attacks
    if skill>=PBTrainerAI.mediumSkill
      if move.pbTargetsAll?(attacker)
        damage=(damage*0.75).round
      end
    end
    #determining if pokemon is grounded
    isgrounded=move.pbTypeModifier(PBTypes::GROUND,opponent,attacker)
    isgrounded = 4 if (isgrounded==0 && attacker.effects[PBEffects::Roost])
    isgrounded = 0 if attacker.effects[PBEffects::MagnetRise]>0
    isgrounded = 0 if attacker.ability == (PBAbilities::LEVITATE)
    isgrounded = 0 if (attitemworks && attacker.item == PBItems::AIRBALLOON)
    # Field Boosts
    if skill>=PBTrainerAI.bestSkill
      case $fefieldeffect
      when 1 # Electric Field
        if type == PBTypes::ELECTRIC
          if isgrounded != 0
            damage=(damage*1.5).floor
          end
        end
      when 2 # Grassy Field
        if type == PBTypes::GRASS
          if isgrounded != 0
            damage=(damage*1.5).floor
          end
        end
        if type == PBTypes::FIRE
          if isgrounded != 0
            damage=(damage*1.5).floor
          end
        end
      when 3 # Misty Field
        if type == PBTypes::DRAGON
          damage=(damage*0.5).floor
        end
      when 4 # Dark Crystal Cavern
        if type == PBTypes::DARK
          damage=(damage*1.5).floor
        end
      when 7 # Burning Field
        if type == PBTypes::FIRE
          if isgrounded != 0
            damage=(damage*1.5).floor
          end
        end
        if type == PBTypes::GRASS
          if isgrounded != 0
            damage=(damage*0.5).floor
          end
        end
        if type == PBTypes::ICE
          damage=(damage*0.5).floor
        end
      when 8 # Swamp Field
        if type == PBTypes::POISON
          if isgrounded != 0
            damage=(damage*1.5).floor
          end
        end
      when 9 # Rainbow Field
        if type == PBTypes::NORMAL &&
          !move.pbIsPhysical?(move.pbBaseType(type))
          damage=(damage*1.5).floor
        end
      when 11 # Corrosive Field
        if type == PBTypes::FIRE
          damage=(damage*1.5).floor
        end
      when 12 # DESERT Field
        if type == PBTypes::WATER
          if isgrounded != 0
            damage=(damage*0.5).floor
          end
        end
        if type == PBTypes::ELECTRIC
          if isgrounded != 0
            damage=(damage*0.5).floor
          end
        end
      when 13 # Icy Field
        if type == PBTypes::FIRE
          damage=(damage*0.5).floor
        end
        if type == PBTypes::ICE
          damage=(damage*1.5).floor
        end
      when 14 # Rocky Field
        if type == PBTypes::ROCK
          damage=(damage*1.5).floor
        end
      when 15 # Forest Field
        if type == PBTypes::GRASS
          damage=(damage*1.5).floor
        end
        if type == PBTypes::BUG &&
          !move.pbIsPhysical?(move.pbBaseType(type))
          damage=(damage*1.5).floor
        end
      when 16 # Superheated Field
        if type == PBTypes::FIRE
          damage=(damage*1.1).floor
        end
        if type == PBTypes::ICE
          damage=(damage*0.5).floor
        end
        if type == PBTypes::WATER
          damage=(damage*0.9).floor
        end
      when 17 # Factory Field
        if type == PBTypes::ELECTRIC
          damage=(damage*1.2).floor
        end
      when 21 # Water Surface
        if type == PBTypes::WATER
          damage=(damage*1.5).floor
        end
        if type == PBTypes::ELECTRIC
          if isgrounded != 0
            damage=(damage*1.5).floor
          end
        end
        if type == PBTypes::FIRE
          if isgrounded != 0
            damage=(damage*0.5).floor
          end
        end
      when 22 # Underwater
        if type == PBTypes::WATER
          damage=(damage*1.5).floor
        end
        if type == PBTypes::ELECTRIC
          damage=(damage*2).floor
        end
      when 23 # Cave
        if type == PBTypes::FLYING && (move.flags&0x01)==0 #not a contact move
          damage=(damage*0.5).floor
        end
        if type == PBTypes::ROCK
          damage=(damage*1.5).floor
        end
      when 24 # Glitch
        if type == PBTypes::PSYCHIC
          damage=(damage*1.2).floor
        end
      when 25 # Crystal Cavern
        if type == PBTypes::ROCK
          damage=(damage*1.5).floor
        end
        if type == PBTypes::DRAGON
          damage=(damage*1.5).floor
        end
      when 26 # Murkwater Surface
        if type == PBTypes::WATER || type == PBTypes::POISON
          damage=(damage*1.5).floor
        end
        if type == PBTypes::ELECTRIC
          if isgrounded != 0
            damage=(damage*1.3).floor
          end
        end
      when 27 # Mountain
        if type == PBTypes::ROCK
          damage=(damage*1.5).floor
        end
        if type == PBTypes::FLYING
          damage=(damage*1.5).floor
        end
        if type == PBTypes::FLYING &&
          !move.pbIsPhysical?(move.pbBaseType(type)) &&
          pbWeather==PBWeather::STRONGWINDS
          damage=(damage*1.5).floor
        end
      when 28 # Snowy Mountain
        if type == PBTypes::ROCK || type == PBTypes::ICE
          damage=(damage*1.5).floor
        end
        if type == PBTypes::FLYING
          damage=(damage*1.5).floor
        end
        if type == PBTypes::FLYING &&
          !move.pbIsPhysical?(move.pbBaseType(type)) &&
          pbWeather==PBWeather::STRONGWINDS
          damage=(damage*1.5).floor
        end
        if type == PBTypes::FIRE
          damage=(damage*0.5).floor
        end
      when 29 # Holy Field
        if (type == PBTypes::GHOST || type == PBTypes::DARK &&
          !move.pbIsPhysical?(move.pbBaseType(type)))
          damage=(damage*0.5).floor
        end
        if (type == PBTypes::FAIRY ||(type == PBTypes::NORMAL) &&
          !move.pbIsPhysical?(move.pbBaseType(type)))
          damage=(damage*1.5).floor
        end
        if type == PBTypes::PSYCHIC || type == PBTypes::DRAGON
          damage=(damage*1.2).floor
        end
      when 31# Fairy Tale
        if type == PBTypes::STEEL
          damage=(damage*1.5).floor
        end
        if type == PBTypes::FAIRY
          damage=(damage*1.5).floor
        end
        if type == PBTypes::DRAGON
          damage=(damage*2).floor
        end
      when 32 # Dragon's Den
        if type == PBTypes::FIRE
          damage=(damage*1.5).floor
        end
          if type == PBTypes::ICE || type == PBTypes::WATER
          damage=(damage*0.5).floor
        end
        if type == PBTypes::DRAGON
          damage=(damage*2).floor
        end
      when 33 # Flower Field
        if type == PBTypes::GRASS
          case $fecounter
            when 1
              damage=(damage*1.2).floor
            when 2
              damage=(damage*1.5).floor
            when 3
              damage=(damage*2).floor
            when 4
              damage=(damage*3).floor
          end
        end
        if $fecounter > 1
          if type == PBTypes::FIRE
            damage=(damage*1.5).floor
          end
        end
        if $fecounter > 3
          if type == PBTypes::BUG
            damage=(damage*2).floor
          end
        elsif $fecounter > 1
          if type == PBTypes::BUG
            damage=(damage*1.5).floor
          end
        end
      when 34 # Starlight Arena
        if type == PBTypes::DARK
          damage=(damage*1.5).floor
        end
          if type == PBTypes::PSYCHIC
          damage=(damage*1.5).floor
        end
        if type == PBTypes::FAIRY
          damage=(damage*1.3).floor
        end
      when 35 # New World
        if type == PBTypes::DARK
          damage=(damage*1.5).floor
        end
      when 37 # Psychic Terrain
        if type == PBTypes::PSYCHIC
          if isgrounded != 0
            damage=(damage*1.5).floor
          end
        end
      end
    end
    if skill>=PBTrainerAI.bestSkill
      # FIELD TRANSFORMATIONS
      case $fefieldeffect
        when 2 # Grassy Field
          if (move.id == PBMoves::HEATWAVE || move.id == PBMoves::ERUPTION ||
           move.id == PBMoves::SEARINGSHOT || move.id == PBMoves::FLAMEBURST ||
           move.id == PBMoves::LAVAPLUME || move.id == PBMoves::FIREPLEDGE ||
           move.id == PBMoves::MINDBLOWN || move.id == PBMoves::INCINERATE) &&
           field.effects[PBEffects::WaterSport] <= 0 &&
           pbWeather != PBWeather::RAINDANCE
            damage=(damage*1.3).floor if damage >= 0
          end
          if (move.id == PBMoves::SLUDGEWAVE)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 3 # Misty Field
          if (move.id == PBMoves::WHIRLWIND || move.id == PBMoves::GUST ||
           move.id == PBMoves::RAZORWIND || move.id == PBMoves::HURRICANE||
           move.id == PBMoves::DEFOG || move.id == PBMoves::TAILWIND ||
           move.id == PBMoves::TWISTER)
            damage=(damage*1.3).floor if damage >= 0
          end
          if (move.id == PBMoves::CLEARSMOG || move.id == PBMoves::SMOG)
            damage=(damage*1.5).floor if damage >= 0
          end
        when 4 # Dark Crystal Cavern
          if (move.id == PBMoves::EARTHQUAKE || move.id == PBMoves::BULLDOZE ||
           move.id == PBMoves::MAGNITUDE)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 5 # Chess Field
          if (move.id == PBMoves::STOMPINGTANTRUM)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 7 # Burning Field
          if (move.id == PBMoves::SLUDGEWAVE)
            damage=(damage*1.3).floor if damage >= 0
          end
          if (move.id == PBMoves::WHIRLWIND || move.id == PBMoves::GUST ||
           move.id == PBMoves::RAZORWIND || move.id == PBMoves::DEFOG ||
           move.id == PBMoves::TAILWIND || move.id == PBMoves::HURRICANE)
            damage=(damage*1.3).floor if damage >= 0
          end
          if (move.id == PBMoves::SURF || move.id == PBMoves::MUDDYWATER ||
           move.id == PBMoves::WATERSPORT || move.id == PBMoves::WATERSPOUT ||
           move.id == PBMoves::WATERPLEDGE || move.id == PBMoves::SPARKLINGARIA)
            damage=(damage*1.3).floor if damage >= 0
          end
          if (move.id == PBMoves::SANDTOMB)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 10 # Corrosive Field
          if (move.id == PBMoves::SEEDFLARE)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 11 # Corrosive Mist Field
          if (move.id == PBMoves::HEATWAVE || move.id == PBMoves::ERUPTION ||
           move.id == PBMoves::SEARINGSHOT || move.id == PBMoves::FLAMEBURST ||
           move.id == PBMoves::LAVAPLUME || move.id == PBMoves::FIREPLEDGE ||
           move.id == PBMoves::EXPLOSION || move.id == PBMoves::SELFDESTRUCT ||
           move.id == PBMoves::TWISTER || move.id == PBMoves::MINDBLOWN ||
           move.id == PBMoves::INCINERATE)
            damage=(damage*1.3).floor if damage >= 0
          end
          if (move.id == PBMoves::GUST || move.id == PBMoves::HURRICANE ||
           move.id == PBMoves::RAZORWIND)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 13 # Icy Field
          if (move.id == PBMoves::HEATWAVE || move.id == PBMoves::ERUPTION ||
           move.id == PBMoves::SEARINGSHOT || move.id == PBMoves::FLAMEBURST ||
           move.id == PBMoves::LAVAPLUME || move.id == PBMoves::FIREPLEDGE ||
           move.id == PBMoves::MINDBLOWN || move.id == PBMoves::INCINERATE)
            damage=(damage*1.3).floor if damage >= 0
          end
          #if (move.id == PBMoves::EARTHQUAKE || move.id == PBMoves::MAGNITUDE ||
          # move.id == PBMoves::BULLDOZE)
          # damage=(damage*1.3).floor if damage >= 0
          #end
        when 15 # Forest Field
          if (move.id == PBMoves::HEATWAVE || move.id == PBMoves::ERUPTION ||
           move.id == PBMoves::SEARINGSHOT || move.id == PBMoves::FLAMEBURST ||
           move.id == PBMoves::LAVAPLUME || move.id == PBMoves::FIREPLEDGE ||
           move.id == PBMoves::MINDBLOWN || move.id == PBMoves::INCINERATE) &&
           field.effects[PBEffects::WaterSport] <= 0
           pbWeather != PBWeather::RAINDANCE
            damage=(damage*1.3).floor if damage >= 0
          end
        when 16 # Superheated Field
          if (move.id == PBMoves::HEATWAVE || move.id == PBMoves::ERUPTION ||
           move.id == PBMoves::SEARINGSHOT || move.id == PBMoves::FLAMEBURST ||
           move.id == PBMoves::SELFDESTRUCT || move.id == PBMoves::EXPLOSION ||
           move.id == PBMoves::LAVAPLUME || move.id == PBMoves::FIREPLEDGE ||
           move.id == PBMoves::MINDBLOWN || move.id == PBMoves::INCINERATE) &&
           pbWeather != PBWeather::RAINDANCE &&
           field.effects[PBEffects::WaterSport] <= 0
            damage=(damage*1.3).floor if damage >= 0
          end
          if (move.id == PBMoves::BLIZZARD || move.id == PBMoves::GLACIATE)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 17 # Factory Field
          if (move.id == PBMoves::DISCHARGE)
            damage=(damage*1.3).floor if damage >= 0
          end
          if (move.id == PBMoves::EXPLOSION || move.id == PBMoves::SELFDESTRUCT ||
           move.id == PBMoves::MAGNITUDE || move.id == PBMoves::EARTHQUAKE ||
           move.id == PBMoves::BULLDOZE)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 18 # Shortcircuit Field
          if (move.id == PBMoves::DISCHARGE)
            damage=(damage*1.3).floor if damage >= 0
          end
          if (move.id == PBMoves::PARABOLICCHARGE ||
           move.id == PBMoves::WILDCHARGE || move.id == PBMoves::CHARGEBEAM)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 21 # Water Surface
          if (move.id == PBMoves::DIVE)
            damage=(damage*1.3).floor if damage >= 0
          end
          if (move.id == PBMoves::BLIZZARD || move.id == PBMoves::GLACIATE)
            damage=(damage*1.3).floor if damage >= 0
          end
          if (move.id == PBMoves::SLUDGEWAVE)
            damage=(damage*1.5).floor if damage >= 0
          end
        when 22 # Underwater
          if (move.id == PBMoves::DIVE || move.id == PBMoves::SKYDROP ||
           move.id == PBMoves::FLY || move.id == PBMoves::BOUNCE)
            damage=(damage*1.3).floor if damage >= 0
          end
          if (move.id == PBMoves::SLUDGEWAVE)
            damage=(damage*2).floor if damage >= 0
          end
        when 23 # Cave Field
          if (move.id == PBMoves::POWERGEM || move.id == PBMoves::DIAMONDSTORM)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 25 # Crystal Cavern
          if (move.id == PBMoves::DARKPULSE || move.id == PBMoves::NIGHTDAZE ||
           move.id == PBMoves::BULLDOZE|| move.id == PBMoves::EARTHQUAKE ||
           move.id == PBMoves::MAGNITUDE)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 26 # Murkwater Surface
          if (move.id == PBMoves::BLIZZARD || move.id == PBMoves::GLACIATE ||
           move.id == PBMoves::WHIRLPOOL)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 27 # Mountain
          if (move.id == PBMoves::BLIZZARD || move.id == PBMoves::GLACIATE)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 28 # Snowy Mountain
          if (move.id == PBMoves::HEATWAVE || move.id == PBMoves::ERUPTION ||
           move.id == PBMoves::SEARINGSHOT || move.id == PBMoves::FLAMEBURST ||
           move.id == PBMoves::LAVAPLUME || move.id == PBMoves::FIREPLEDGE ||
           move.id == PBMoves::MINDBLOWN || move.id == PBMoves::INCINERATE)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 30 # Mirror Arena
          if (move.id == PBMoves::BOOMBURST || move.id == PBMoves::BULLDOZE ||
           move.id == PBMoves::HYPERVOICE || move.id == PBMoves::EARTHQUAKE ||
           move.id == PBMoves::EXPLOSION || move.id == PBMoves::SELFDESTRUCT ||
           move.id == PBMoves::MAGNITUDE)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 32 # Dragon's Den
          if (move.id == PBMoves::GLACIATE)
            damage=(damage*1.3).floor if damage >= 0
          end
        when 33 # Flower Garden Field
          if $fecounter > 1
            if (move.id == PBMoves::HEATWAVE || move.id == PBMoves::ERUPTION ||
             move.id == PBMoves::SEARINGSHOT || move.id == PBMoves::FLAMEBURST ||
             move.id == PBMoves::LAVAPLUME || move.id == PBMoves::FIREPLEDGE ||
             move.id == PBMoves::MINDBLOWN || move.id == PBMoves::INCINERATE) &&
             field.effects[PBEffects::WaterSport] <= 0 &&
             pbWeather != PBWeather::RAINDANCE
              damage=(damage*1.3).floor if damage >= 0
            end
          end
      end
    end
    # Weather
    if skill>=PBTrainerAI.mediumSkill
      case pbWeather
        when PBWeather::SUNNYDAY
          if field.effects[PBEffects::HarshSunlight] &&
             type == PBTypes::WATER
            damage=0
          end
          if type == PBTypes::FIRE
            damage=(damage*1.5).round
          elsif type == PBTypes::WATER
            damage=(damage*0.5).round
          end
        when PBWeather::RAINDANCE
          if field.effects[PBEffects::HeavyRain] &&
          type == PBTypes::FIRE
            damage=0
          end
          if type == PBTypes::FIRE
            damage=(damage*0.5).round
          elsif type == PBTypes::WATER
            damage=(damage*1.5).round
          end
       end
    end

    outgoingdamage = false
    if attacker.index == 2 && pbOwnedByPlayer?(attacker.index) == false
      if opponent.index==1 || opponent.index==3
        outgoingdamage = true
      end
    else
      if opponent.index==0 || opponent.index==2
        outgoingdamage = true
      end
    end
    if outgoingdamage == true
      random=85
      damage=(damage*random/100.0).floor
    end
    # Water Bubble
    if skill>=PBTrainerAI.mediumSkill
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::WATERBUBBLE) && type == PBTypes::WATER
        damage=(damage*=2).round
      end
      # STAB
      if (attacker.pbHasType?(type) || (!attacker.abilitynulled && attacker.ability == PBAbilities::PROTEAN))
        if (!attacker.abilitynulled && attacker.ability == PBAbilities::ADAPTABILITY)
          damage=(damage*2).round
        else
          damage=(damage*1.5).round
        end
      elsif ((!attacker.abilitynulled && attacker.ability == PBAbilities::STEELWORKER) && type == PBTypes::STEEL)
        if $fefieldeffect==17 # Factory Field
          damage=(damage*2).round
        else
          damage=(damage*1.5).round
        end
      end
    end
    # Type effectiveness
    #typemod=pbTypeModifier(type,attacker,opponent)
    typemod=pbTypeModNoMessages(type,attacker,opponent,move,skill)
    if skill>=PBTrainerAI.minimumSkill
      damage=(damage*typemod/4.0).round
    end
    # Water Bubble
    if skill>=PBTrainerAI.mediumSkill
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::WATERBUBBLE) && type == PBTypes::FIRE
        damage=(damage*=0.5).round
      end
      # Burn
      if attacker.status==PBStatuses::BURN && move.pbIsPhysical?(type) &&
         !(!attacker.abilitynulled && attacker.ability == PBAbilities::GUTS)
        damage=(damage*0.5).round
      end
    end
    # Make sure damage is at least 1
    damage=1 if damage<1
    # Screens
    if skill>=PBTrainerAI.highSkill
      if move.pbIsPhysical?(type)
        if opponent.pbOwnSide.effects[PBEffects::Reflect]>0 || opponent.pbOwnSide.effects[PBEffects::AuroraVeil]>0
          if !opponent.pbPartner.isFainted?
            damage=(damage*0.66).round
          else
            damage=(damage*0.5).round
          end
        end
      elsif move.pbIsSpecial?(type)
        if opponent.pbOwnSide.effects[PBEffects::Reflect]>0 || opponent.pbOwnSide.effects[PBEffects::AuroraVeil]>0
          if !opponent.pbPartner.isFainted?
            damage=(damage*0.66).round
          else
            damage=(damage*0.5).round
          end
        end
      end
    end

    # Multiscale
    if skill>=PBTrainerAI.mediumSkill
      if !opponent.abilitynulled
        if opponent.ability == PBAbilities::MULTISCALE || opponent.ability == PBAbilities::SHADOWSHIELD
          if opponent.hp==opponent.totalhp
            damage=(damage*0.5).round
          end
        
        elsif opponent.ability == PBAbilities::SOLIDROCK || opponent.ability == PBAbilities::FILTER || opponent.ability == PBAbilities::PRISMARMOR
          if typemod>4
            damage=(damage*0.75).round
          end
        end
      end
      if (!opponent.pbPartner.abilitynulled && opponent.pbPartner.ability == PBAbilities::FRIENDGUARD)
        damage=(damage*0.75).round
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::STAKEOUT) && switchedOut[opponent.index]
        damage=(damage*2.0).round
      end
    end
    
    # Tinted Lens
    if skill>=PBTrainerAI.mediumSkill
      if !attacker.abilitynulled && attacker.ability == PBAbilities::TINTEDLENS && typemod<4
        damage=(damage*2.0).round
      end
    end
    
    # Neuroforce
    if skill>=PBTrainerAI.mediumSkill
      if !attacker.abilitynulled && attacker.ability == PBAbilities::NEUROFORCE && typemod>4
        damage=(damage*1.25).round
      end 
    end 

    # Flower Veil + Flower Garden Shenanigans
    if skill>=PBTrainerAI.bestSkill
      if $fefieldeffect == 33 && $fecounter >1
        if ((!opponent.pbPartner.abilitynulled && opponent.pbPartner.ability == PBAbilities::FLOWERVEIL) &&
         opponent.pbHasType?(:GRASS)) ||
         (!opponent.abilitynulled && opponent.ability == PBAbilities::FLOWERVEIL)
          damage=(damage*0.5).round
        end
        case $fecounter
        when 2
          if opponent.pbHasType?(:GRASS)
            damage=(damage*0.75).round
          end
        when 3
          if opponent.pbHasType?(:GRASS)
            damage=(damage*0.67).round
          end
        when 4
          if opponent.pbHasType?(:GRASS)
            damage=(damage*0.5).round
          end
        end
      end
    end
    # Final damage-altering items
    if skill>=PBTrainerAI.highSkill
      if (attitemworks && attacker.item == PBItems::METRONOME)
        if attacker.effects[PBEffects::Metronome]>4
          damage=(damage*2.0).round
        else
          met=1.0+attacker.effects[PBEffects::Metronome]*0.2
          damage=(damage*met).round
        end
      elsif (attitemworks && attacker.item == PBItems::EXPERTBELT) && typemod>4
        damage=(damage*1.2).round
      elsif (attitemworks && attacker.item == PBItems::LIFEORB)
        damage=(damage*1.3).round
      elsif typemod>4 && oppitemworks
        #SE Damage reducing berries
        if (opponent.item == (PBItems::CHOPLEBERRY) && type == PBTypes::FIGHTING) ||
           (opponent.item == (PBItems::COBABERRY) && type == PBTypes::FLYING) ||
           (opponent.item == (PBItems::KEBIABERRY) && type == PBTypes::POISON) ||
           (opponent.item == (PBItems::SHUCABERRY) && (type == PBTypes::GROUND)) ||
           (opponent.item == (PBItems::CHARTIBERRY) && type == PBTypes::ROCK) ||
           (opponent.item == (PBItems::TANGABERRY) && type == PBTypes::BUG) ||
           (opponent.item == (PBItems::KASIBBERRY) && type == PBTypes::GHOST) ||
           (opponent.item == (PBItems::BABIRIBERRY) && type == PBTypes::STEEL) ||
           (opponent.item == (PBItems::OCCABERRY) && type == PBTypes::FIRE) ||
           (opponent.item == (PBItems::PASSHOBERRY) && type == PBTypes::WATER) ||
           (opponent.item == (PBItems::RINDOBERRY) && type == PBTypes::GRASS) ||
           (opponent.item == (PBItems::WACANBERRY) && type == PBTypes::ELECTRIC) ||
           (opponent.item == (PBItems::PAYAPABERRY) && type == PBTypes::PSYCHIC) ||
           (opponent.item == (PBItems::YACHEBERRY) && type == PBTypes::ICE) ||
           (opponent.item == (PBItems::HABANBERRY) && type == PBTypes::DRAGON) ||
           (opponent.item == (PBItems::COLBURBERRY) && type == PBTypes::DARK) ||
           (opponent.item == (PBItems::ROSELIBERRY) && type == PBTypes::FAIRY)
          if opponent.ability == (PBAbilities::RIPEN)
            damage=(damage*0.25).round
          else
            damage=(damage*0.5).round
          end
        end
      end
    end
    # pbModifyDamage - TODO
    # "AI-specific calculations below"
    # Increased critical hit rates
    if skill>=PBTrainerAI.mediumSkill
      critrate = pbAICritRate(attacker,opponent,move)
      if critrate==2
        damage=(damage*1.25).round
      elsif critrate>2
        damage=(damage*1.5).round
      end
    end
    attacker.pbUpdate(true) if defined?(megaEvolved) && megaEvolved==true #un-mega pokemon #perry
    return damage
  end

  def pbTypeModNoMessages(type,attacker,opponent,move,skill)
    return 4 if type<0
    id = move.id

    if !attacker.abilitynulled
      type=PBTypes::ELECTRIC if type == PBTypes::NORMAL && attacker.ability == PBAbilities::GALVANIZE
      type=PBTypes::FLYING if type == PBTypes::NORMAL && attacker.ability == PBAbilities::AERILATE
      type=PBTypes::FAIRY if type == PBTypes::NORMAL && attacker.ability == PBAbilities::PIXILATE
      type=PBTypes::ICE if type == PBTypes::NORMAL && attacker.ability == PBAbilities::REFRIGERATE
      type=PBTypes::NORMAL if attacker.ability == PBAbilities::NORMALIZE
    end
    if !opponent.abilitynulled && !(opponent.moldbroken)
      if opponent.ability == PBAbilities::SAPSIPPER 
        return 0 if type == PBTypes::GRASS || move.FieldTypeChange(attacker,opponent,1,true)==PBTypes::GRASS
      elsif opponent.ability == PBAbilities::LEVITATE 
        return 0 if type == PBTypes::GROUND || move.FieldTypeChange(attacker,opponent,1,true)==PBTypes::GROUND
      elsif opponent.ability == PBAbilities::STORMDRAIN
        return 0 if type == PBTypes::WATER || move.FieldTypeChange(attacker,opponent,1,true)==PBTypes::WATER
      elsif opponent.ability == PBAbilities::LIGHTNINGROD 
        return 0 if type == PBTypes::ELECTRIC || move.FieldTypeChange(attacker,opponent,1,true)==PBTypes::ELECTRIC
      elsif opponent.ability == PBAbilities::MOTORDRIVE
        return 0 if type == PBTypes::ELECTRIC || move.FieldTypeChange(attacker,opponent,1,true)==PBTypes::ELECTRIC
      elsif opponent.ability == PBAbilities::DRYSKIN 
        return 0 if type == PBTypes::WATER || move.FieldTypeChange(attacker,opponent,1,true)==PBTypes::WATER && opponent.effects[PBEffects::HealBlock]==0
      elsif opponent.ability == PBAbilities::VOLTABSORB
        return 0 if type == PBTypes::ELECTRIC || move.FieldTypeChange(attacker,opponent,1,true)==PBTypes::ELECTRIC && opponent.effects[PBEffects::HealBlock]==0
      elsif opponent.ability == PBAbilities::WATERABSORB 
        return 0 if type == PBTypes::WATER || move.FieldTypeChange(attacker,opponent,1,true)==PBTypes::WATER && opponent.effects[PBEffects::HealBlock]==0
      elsif opponent.ability == PBAbilities::BULLETPROOF
        return 0 if (PBStuff::BULLETMOVE).include?(id)
      elsif opponent.ability == PBAbilities::FLASHFIRE
        return 0 if type == PBTypes::FIRE || move.FieldTypeChange(attacker,opponent,1,true)==PBTypes::FIRE
      elsif opponent.ability == PBAbilities::MAGMAARMOR
        return 0 if (type == PBTypes::FIRE || move.FieldTypeChange(attacker,opponent,1,true)==PBTypes::FIRE) && $fefieldeffect == 32
      elsif move.basedamage>0 && opponent.ability == PBAbilities::TELEPATHY
        partner=attacker.pbPartner
        if opponent.index == partner.index
          return 0
        end
      end
    end
    if $fefieldeffect == 14 && (opponent.effects[PBEffects::Substitute]>0 || opponent.stages[PBStats::EVASION] > 0)
      return 0 if (PBStuff::BULLETMOVE).include?(id)
    end
    if ($fefieldeffect == 21 || $fefieldeffect == 26) &&
      ((type == PBTypes::GROUND) || move.FieldTypeChange(attacker,opponent,1,true)==PBTypes::GROUND)
      return 0
    end
    if $fefieldeffect == 22 && (type == PBTypes::FIRE || move.FieldTypeChange(attacker,opponent,1,true)==PBTypes::FIRE)
      return 0
    end
    # UPDATE Implementing Flying Press + Freeze Dry
    faintedcount=0
    for i in pbParty(opponent.index)
      next if i.nil?
      faintedcount+=1 if (i.hp==0 && i.hp!=0)
    end
    if opponent.effects[PBEffects::Illusion]
      if skill>=PBTrainerAI.bestSkill
        if !(opponent.turncount>1 || faintedcount>2)
          zorovar=true
        else
          zorovar=false
        end
      elsif skill>=PBTrainerAI.highSkill
        if !(faintedcount>4)
          zorovar=true
        else
          zorovar=false
        end
      else
        zorovar = true
      end
    else
      zorovar=false
    end
    typemod=move.pbTypeModifier(type,attacker,opponent,zorovar)
    typemod2= nil
    typemod3= nil
    if type == PBTypes::WATER &&
     (opponent.pbHasType?(PBTypes::WATER)) &&
      $fefieldeffect == 22
      typemod*= 2
    end
    if $fefieldeffect == 24
      if type == PBTypes::DRAGON
        typemod = 4
      end
      if type == PBTypes::GHOST && (opponent.pbHasType?(PBTypes::PSYCHIC))
        typemod = 0
      end
      if type == PBTypes::BUG && (opponent.pbHasType?(PBTypes::POISON))
        typemod*= 4
      end
      if type == PBTypes::ICE && (opponent.pbHasType?(PBTypes::FIRE))
        typemod*= 2
      end
      if type == PBTypes::POISON && (opponent.pbHasType?(PBTypes::BUG))
        typemod*= 2
      end
    end
    if $fefieldeffect == 29
      if type == PBTypes::NORMAL && (opponent.pbHasType?(PBTypes::DARK) ||
       opponent.pbHasType?(PBTypes::GHOST))
        typemod*= 2
      end
    end
    if $fefieldeffect == 31
      if type == PBTypes::STEEL && (opponent.pbHasType?(PBTypes::DRAGON))
        typemod*= 2
      end
    end
    if id == PBMoves::FREEZEDRY && (opponent.pbHasType?(PBTypes::WATER))
      typemod*= 4
    end
    if id == PBMoves::CUT && (opponent.pbHasType?(PBTypes::GRASS)) &&
     $fefieldeffect == 33 && $fecounter > 0
      typemod*= 2
    end
    if pbWeather==PBWeather::STRONGWINDS &&
     ((opponent.pbHasType?(PBTypes::FLYING)) &&
     !opponent.effects[PBEffects::Roost]) &&
     (type == PBTypes::ELECTRIC || type == PBTypes::ICE ||
     type == PBTypes::ROCK)
      typemod /= 2
    end
    if $fefieldeffect == 32 && # Dragons Den Multiscale
     (!opponent.abilitynulled && opponent.ability == PBAbilities::MULTISCALE) &&
     (type == PBTypes::FAIRY || type == PBTypes::ICE ||
     type == PBTypes::DRAGON) && !(opponent.moldbroken)
      typemod /= 2
    end
    if id == PBMoves::FLYINGPRESS
      typemod2=move.pbTypeModifier(PBTypes::FLYING,attacker,opponent,zorovar)
      typemod3= ((typemod*typemod2)/4.0)
      typemod=typemod3
    end
    # Field Effect type changes go here
    typemod=move.FieldTypeChange(attacker,opponent,typemod,false)
    if typemod==0
      if @function==0x111
        return 1
      end
    end
    return typemod
  end

  def pbAICritRate(attacker,opponent,move)
    if ((!opponent.abilitynulled && opponent.ability == PBAbilities::BATTLEARMOR) ||
        (!opponent.abilitynulled && opponent.ability == PBAbilities::SHELLARMOR)) &&
        !(opponent.moldbroken)
            return 0
    end
    return 0 if opponent.pbOwnSide.effects[PBEffects::LuckyChant]>0
    $buffs = 0
    if $fefieldeffect == 30
      $buffs = attacker.stages[PBStats::EVASION] if attacker.stages[PBStats::EVASION] > 0
      $buffs = $buffs.to_i + attacker.stages[PBStats::ACCURACY] if attacker.stages[PBStats::ACCURACY] > 0
      $buffs = $buffs.to_i - opponent.stages[PBStats::EVASION] if opponent.stages[PBStats::EVASION] < 0
      $buffs = $buffs.to_i - opponent.stages[PBStats::ACCURACY] if opponent.stages[PBStats::ACCURACY] < 0
      $buffs = $buffs.to_i
    end
    if attacker.effects[PBEffects::LaserFocus]>0
      return 3
    end
    return 3 if move.function==0xA0 # Frost Breath
    return 3 if (!attacker.abilitynulled && attacker.ability == PBAbilities::MERCILESS) && (opponent.status == PBStatuses::POISON ||
    $fefieldeffect==10 || $fefieldeffect==11 || $fefieldeffect==19 || $fefieldeffect==26)
    c=0
    c+=attacker.effects[PBEffects::FocusEnergy]
    c+=1 if move.hasHighCriticalRate?
    c+=1 if (!attacker.abilitynulled && attacker.ability == PBAbilities::SUPERLUCK)
    if (attacker.species == PBSpecies::FARFETCHD) && attacker.hasWorkingItem(:STICK)
      c+=2
    end
    if (attacker.species == PBSpecies::CHANSEY) && attacker.hasWorkingItem(:LUCKYPUNCH)
      c+=2
    end
    c+=1 if attacker.hasWorkingItem(:RAZORCLAW)
    c+=1 if attacker.hasWorkingItem(:SCOPELENS)
    c+=1 if attacker.speed > opponent.speed && $fefieldeffect == 24
    if $fefieldeffect == 30
      c += $buffs if $buffs > 0
    end
    c=3 if c>3
    return c
  end

  def pbRoughAccuracy(move,attacker,opponent,skill)
    # Get base accuracy
    baseaccuracy=move.accuracy
    if skill>=PBTrainerAI.mediumSkill
      if pbWeather==PBWeather::SUNNYDAY &&
         (move.function==0x08 || move.function==0x15) # Thunder, Hurricane
        accuracy=50
      end
    end
    # Accuracy stages
    accstage=attacker.stages[PBStats::ACCURACY]
    accstage=0 if (!opponent.abilitynulled && opponent.ability == PBAbilities::UNAWARE)
    accuracy=(accstage>=0) ? (accstage+3)*100.0/3 : 300.0/(3-accstage)
    evastage=opponent.stages[PBStats::EVASION]
    evastage-=2 if @field.effects[PBEffects::Gravity]>0
    evastage=-6 if evastage<-6
    evastage=0 if opponent.effects[PBEffects::Foresight] ||
                  opponent.effects[PBEffects::MiracleEye] ||
                  move.function==0xA9 || # Chip Away
                  (!attacker.abilitynulled && attacker.ability == PBAbilities::UNAWARE)
    evasion=(evastage>=0) ? (evastage+3)*100.0/3 : 300.0/(3-evastage)
    accuracy*=baseaccuracy/evasion
    # Accuracy modifiers
    if skill>=PBTrainerAI.mediumSkill
      accuracy*=1.3 if (!attacker.abilitynulled && attacker.ability == PBAbilities::COMPOUNDEYES)
      
      accuracy*=1.1 if (!attacker.abilitynulled && attacker.ability == PBAbilities::VICTORYSTAR)
      if skill>=PBTrainerAI.highSkill
        partner=attacker.pbPartner
        accuracy*=1.1 if partner && (!partner.abilitynulled && partner.ability == PBAbilities::VICTORYSTAR)
      end
      
      if skill>=PBTrainerAI.highSkill
        accuracy*=0.8 if (!attacker.abilitynulled && attacker.ability == PBAbilities::HUSTLE) &&
                         move.basedamage>0 && move.pbIsPhysical?(move.pbBaseType(move.type))
      end
      if skill>=PBTrainerAI.bestSkill
        accuracy/=2 if (!opponent.abilitynulled && opponent.ability == PBAbilities::WONDERSKIN) &&
                       move.basedamage==0 && attacker.opposes?(opponent.index)
        accuracy/=1.2 if (!opponent.abilitynulled && opponent.ability == PBAbilities::TANGLEDFEET) &&
                         opponent.effects[PBEffects::Confusion]>0
        accuracy/=1.2 if pbWeather==PBWeather::SANDSTORM &&
                         (!opponent.abilitynulled && opponent.ability == PBAbilities::SANDVEIL)
        accuracy/=1.2 if pbWeather==PBWeather::HAIL &&
                         (!opponent.abilitynulled && opponent.ability == PBAbilities::SNOWCLOAK)
      end
      if attacker.itemWorks?
        accuracy*=1.1 if attacker.item == PBItems::WIDELENS
        accuracy*=1.2 if attacker.item == PBItems::ZOOMLENS && attacker.pbSpeed<opponent.pbSpeed
        if attacker.item == PBItems::MICLEBERRY
          accuracy*=1.2 if ((!attacker.abilitynulled && attacker.ability == PBAbilities::GLUTTONY) &&
                          attacker.hp<=(attacker.totalhp/2.0).floor) ||
                          attacker.hp<=(attacker.totalhp/4.0).floor
        end
        if skill>=PBTrainerAI.highSkill
          accuracy/=1.1 if opponent.item == PBItems::BRIGHTPOWDER
          accuracy/=1.1 if opponent.item == PBItems::LAXINCENSE
        end
      end
    end
    # Override accuracy
    accuracy=100 if move.accuracy==0   # Doesn't do accuracy check (always hits)
    accuracy=100 if move.function==0xA5 # Swift
    if skill>=PBTrainerAI.mediumSkill
      accuracy=100 if opponent.effects[PBEffects::LockOn]>0 &&
                      opponent.effects[PBEffects::LockOnPos]==attacker.index
      if skill>=PBTrainerAI.highSkill
        accuracy=100 if (!attacker.abilitynulled && attacker.ability == PBAbilities::NOGUARD) ||
                        (!opponent.abilitynulled && opponent.ability == PBAbilities::NOGUARD)
      end
      accuracy=100 if opponent.effects[PBEffects::Telekinesis]>0
      case pbWeather
        when PBWeather::HAIL
          accuracy=100 if move.function==0x0D # Blizzard
        when PBWeather::RAINDANCE
          accuracy=100 if move.function==0x08 || move.function==0x15 # Thunder, Hurricane
      end
          accuracy=100 if (move.function==0x08 || move.function==0x15) && # Thunder, Hurricane
              ($fefieldeffect == 27 || $fefieldeffect == 28)
      if move.function==0x70 # OHKO moves
        accuracy=move.accuracy+attacker.level-opponent.level
        accuracy=0 if (!opponent.abilitynulled && opponent.ability == PBAbilities::STURDY)
        accuracy=0 if opponent.level>attacker.level
      end
    end
    accuracy=100 if accuracy>100
    return accuracy
  end

  def pbGetMonRole(mon,opponent,skill,position=0,party=nil)
    #PBDebug.log(sprintf("Beginning role assignment for %s",PBSpecies.getName(mon.species))) if $INTERNAL
    monRoles=[]
    monability = mon.ability.to_i
    curemove=false
    healingmove=false
    wishmove=false
    phasemove=false
    priorityko=false
    pivotmove=false
    spinmove=false
    batonmove=false
    tauntmove=false
    restmove=false
    weathermove=false
    fieldmove=false
    if mon.class == PokeBattle_Battler
      if mon.ev[3]>251 && (mon.nature==PBNatures::MODEST ||
        mon.nature==PBNatures::JOLLY || mon.nature==PBNatures::TIMID ||
        mon.nature==PBNatures::ADAMANT) || (mon.item==(PBItems::CHOICEBAND) ||
        mon.item==(PBItems::CHOICESPECS) || mon.item==(PBItems::CHOICESCARF))
        monRoles.push(PBMonRoles::SWEEPER)
      end
      for i in mon.moves
        next if i.nil?
        next if i.id == 0
        if i.priority>0
          dam=pbRoughDamage(i,mon,opponent,skill,i.basedamage)
          if opponent.hp>0
            percentage=(dam*100.0)/opponent.hp
            priorityko=true if percentage>100
          end
        end
        if i.isHealingMove?
          healingmove=true
        elsif (i.id == (PBMoves::HEALBELL) || i.id == (PBMoves::AROMATHERAPY))
          curemove=true
        elsif (i.id == (PBMoves::WISH))
          wishmove=true
        elsif (i.id == (PBMoves::YAWN) || i.id == (PBMoves::PERISHSONG) ||
          i.id == (PBMoves::DRAGONTAIL) || i.id == (PBMoves::CIRCLETHROW) ||
          i.id == (PBMoves::WHIRLWIND) || i.id == (PBMoves::ROAR))
           phasemove=true
        elsif (i.id == (PBMoves::UTURN) || i.id == (PBMoves::VOLTSWITCH))
          pivotmove=true
        elsif (i.id == (PBMoves::RAPIDSPIN))
          spinmove=true
        elsif (i.id == (PBMoves::BATONPASS))
          batonmove=true
        elsif (i.id == (PBMoves::TAUNT))
          tauntmove=true
        elsif (i.id == (PBMoves::REST))
          restmove=true
        elsif (i.id == (PBMoves::SUNNYDAY) || i.id == (PBMoves::RAINDANCE) ||
          i.id == (PBMoves::HAIL) || i.id == (PBMoves::SANDSTORM))
          weathermove=true
        elsif (i.id == (PBMoves::GRASSYTERRAIN) || i.id == (PBMoves::ELECTRICTERRAIN) ||
          i.id == (PBMoves::MISTYTERRAIN) || i.id == (PBMoves::PSYCHICTERRAIN) ||
          i.id == (PBMoves::MIST) || i.id == (PBMoves::IONDELUGE) ||
          i.id == (PBMoves::TOPSYTURVY))
          fieldmove=true
        end
      end
      if healingmove && (mon.ev[2]>251 && (mon.nature==PBNatures::BOLD ||
        mon.nature==PBNatures::RELAXED || mon.nature==PBNatures::IMPISH ||
        mon.nature==PBNatures::LAX))
        monRoles.push(PBMonRoles::PHYSICALWALL)
      end
      if healingmove && (mon.ev[5]>251 && (mon.nature==PBNatures::CALM ||
        mon.nature==PBNatures::GENTLE || mon.nature==PBNatures::SASSY ||
        mon.nature==PBNatures::CAREFUL))
        monRoles.push(PBMonRoles::SPECIALWALL)
      end
      if mon.pokemonIndex==0
        monRoles.push(PBMonRoles::LEAD)
      end
      if curemove || (wishmove && mon.ev[0]>251)
        monRoles.push(PBMonRoles::CLERIC)
      end
      if phasemove == true
        monRoles.push(PBMonRoles::PHAZER)
      end
      if mon.item==(PBItems::LIGHTCLAY)
        monRoles.push(PBMonRoles::SCREENER)
      end
      if priorityko || (mon.speed>opponent.speed)
        monRoles.push(PBMonRoles::REVENGEKILLER)
      end
      if (pivotmove && healingmove) || (monability == PBAbilities::REGENERATOR)
        monRoles.push(PBMonRoles::PIVOT)
      end
      if spinmove
        monRoles.push(PBMonRoles::SPINNER)
      end
      if (mon.ev[0]>251 && !healingmove) || mon.item==(PBItems::ASSAULTVEST)
        monRoles.push(PBMonRoles::TANK)
      end
      if batonmove
        monRoles.push(PBMonRoles::BATONPASSER)
      end
      if tauntmove || mon.item==(PBItems::CHOICEBAND) ||
        mon.item==(PBItems::CHOICESPECS)
        monRoles.push(PBMonRoles::STALLBREAKER)
      end
      if restmove || (monability == PBAbilities::COMATOSE) || mon.item==(PBItems::TOXICORB) || mon.item==(PBItems::FLAMEORB) || (monability == PBAbilities::GUTS) || (monability == PBAbilities::QUICKFEET)|| (monability == PBAbilities::FLAREBOOST) || (monability == PBAbilities::TOXICBOOST) || (monability == PBAbilities::NATURALCURE) || (monability == PBAbilities::MAGICGUARD) || (monability == PBAbilities::MAGICBOUNCE) || ((monability == PBAbilities::HYDRATION) && pbWeather==PBWeather::RAINDANCE)
        monRoles.push(PBMonRoles::STATUSABSORBER)
      end
      if (monability == PBAbilities::SHADOWTAG) || (monability == PBAbilities::ARENATRAP) || (monability == PBAbilities::MAGNETPULL)
        monRoles.push(PBMonRoles::TRAPPER)
      end
      if weathermove || (monability == PBAbilities::DROUGHT) || (monability == PBAbilities::SANDSTREAM) || (monability == PBAbilities::DRIZZLE) || (monability == PBAbilities::SNOWWARNING) || (monability == PBAbilities::PRIMORDIALSEA) || (monability == PBAbilities::DESOLATELAND) || (monability == PBAbilities::DELTASTREAM)
        monRoles.push(PBMonRoles::WEATHERSETTER)
      end
      if fieldmove || (monability == PBAbilities::GRASSYSURGE) || (monability == PBAbilities::ELECTRICSURGE) || (monability == PBAbilities::MISTYSURGE) || (monability == PBAbilities::PSYCHICSURGE) || mon.item==(PBItems::AMPLIFIELDROCK)
        monRoles.push(PBMonRoles::FIELDSETTER)
      end
      #if $game_switches[525] && mon.pokemonIndex==(pbParty(mon.index).length-1)
      if mon.pokemonIndex==(pbParty(mon.index).length-1)
        monRoles.push(PBMonRoles::ACE)
      end
      secondhighest=true
      if pbParty(mon.index).length>2
        for i in 0..(pbParty(mon.index).length-2)
          next if pbParty(mon.index)[i].nil?
          if mon.level<pbParty(mon.index)[i].level
            secondhighest=false
          end
        end
      end
      #if $game_switches[525]&& secondhighest
      if secondhighest
        monRoles.push(PBMonRoles::SECOND)
      end
      #PBDebug.log(sprintf("Ending role assignment for %s",PBSpecies.getName(mon.species))) if $INTERNAL
      #PBDebug.log(sprintf("")) if $INTERNAL
      return monRoles
    elsif mon.class == PokeBattle_Pokemon
      movelist = []
      for i in mon.moves
        next if i.nil?
        next if i.id == 0
        movedummy = PokeBattle_Move.pbFromPBMove(self,i)
        movelist.push(movedummy)
      end
      if mon.ev[3]>251 && (mon.nature==PBNatures::MODEST ||
        mon.nature==PBNatures::JOLLY || mon.nature==PBNatures::TIMID ||
        mon.nature==PBNatures::ADAMANT) || (mon.item==(PBItems::CHOICEBAND) ||
        mon.item==(PBItems::CHOICESPECS) || mon.item==(PBItems::CHOICESCARF))
        monRoles.push(PBMonRoles::SWEEPER)
      end
      for i in movelist
        next if i.nil?
        if i.isHealingMove?
          healingmove=true
        elsif (i.id == (PBMoves::HEALBELL) || i.id == (PBMoves::AROMATHERAPY))
          curemove=true
        elsif (i.id == (PBMoves::WISH))
          wishmove=true
        elsif (i.id == (PBMoves::YAWN) || i.id == (PBMoves::PERISHSONG) ||
          i.id == (PBMoves::DRAGONTAIL) || i.id == (PBMoves::CIRCLETHROW) ||
          i.id == (PBMoves::WHIRLWIND) || i.id == (PBMoves::ROAR))
           phasemove=true
        elsif (i.id == (PBMoves::UTURN) || i.id == (PBMoves::VOLTSWITCH))
          pivotmove=true
        elsif (i.id == (PBMoves::RAPIDSPIN))
          spinmove=true
        elsif (i.id == (PBMoves::BATONPASS))
          batonmove=true
        elsif(i.id == (PBMoves::TAUNT))
          tauntmove=true
        elsif (i.id == (PBMoves::REST))
          restmove=true
        elsif (i.id == (PBMoves::SUNNYDAY) || i.id == (PBMoves::RAINDANCE) ||
          i.id == (PBMoves::HAIL) || i.id == (PBMoves::SANDSTORM))
          weathermove=true
        elsif (i.id == (PBMoves::GRASSYTERRAIN) || i.id == (PBMoves::ELECTRICTERRAIN) ||
          i.id == (PBMoves::MISTYTERRAIN) || i.id == (PBMoves::PSYCHICTERRAIN) ||
          i.id == (PBMoves::MIST) || i.id == (PBMoves::IONDELUGE) ||
          i.id == (PBMoves::TOPSYTURVY))
          fieldmove=true
        end
      end
      if healingmove && (mon.ev[2]>251 && (mon.nature==PBNatures::BOLD ||
        mon.nature==PBNatures::RELAXED || mon.nature==PBNatures::IMPISH ||
        mon.nature==PBNatures::LAX))
        monRoles.push(PBMonRoles::PHYSICALWALL)
      end
      if healingmove && (mon.ev[5]>251 && (mon.nature==PBNatures::CALM ||
        mon.nature==PBNatures::GENTLE || mon.nature==PBNatures::SASSY ||
        mon.nature==PBNatures::CAREFUL))
        monRoles.push(PBMonRoles::SPECIALWALL)
      end
      if position==0
        monRoles.push(PBMonRoles::LEAD)
      end
      if (phasemove)
        monRoles.push(PBMonRoles::PHAZER)
      end
      if mon.item==(PBItems::LIGHTCLAY)
        monRoles.push(PBMonRoles::SCREENER)
      end
      # pbRoughDamage does not take Pokemon objects, this will cause issues
      priorityko=false
      for i in movelist
        next if i.priority<1
        next if i.basedamage<10
        priorityko=true
      end
      if priorityko || (mon.speed>opponent.speed)
        monRoles.push(PBMonRoles::REVENGEKILLER)
      end
      if (pivotmove && healingmove) || (monability == PBAbilities::REGENERATOR)
        monRoles.push(PBMonRoles::PIVOT)
      end
      if spinmove
        monRoles.push(PBMonRoles::SPINNER)
      end
      if (mon.ev[0]>251 && !healingmove) || mon.item==(PBItems::ASSAULTVEST)
        monRoles.push(PBMonRoles::TANK)
      end
      if batonmove
        monRoles.push(PBMonRoles::BATONPASSER)
      end
      if tauntmove || mon.item==(PBItems::CHOICEBAND) ||
        mon.item==(PBItems::CHOICESPECS)
        monRoles.push(PBMonRoles::STALLBREAKER)
      end
      if restmove || (monability == PBAbilities::COMATOSE) || mon.item==(PBItems::TOXICORB) || mon.item==(PBItems::FLAMEORB) || (monability == PBAbilities::GUTS) || (monability == PBAbilities::QUICKFEET)|| (monability == PBAbilities::FLAREBOOST) || (monability == PBAbilities::TOXICBOOST) || (monability == PBAbilities::NATURALCURE) || (monability == PBAbilities::MAGICGUARD) || (monability == PBAbilities::MAGICBOUNCE) || ((monability == PBAbilities::HYDRATION) && pbWeather==PBWeather::RAINDANCE)
        monRoles.push(PBMonRoles::STATUSABSORBER)
      end
      if (monability == PBAbilities::SHADOWTAG) || (monability == PBAbilities::ARENATRAP) || (monability == PBAbilities::MAGNETPULL)
        monRoles.push(PBMonRoles::TRAPPER)
      end
      if weathermove || (monability == PBAbilities::DROUGHT) || (monability == PBAbilities::SANDSTREAM) || (monability == PBAbilities::DRIZZLE) || (monability == PBAbilities::SNOWWARNING) || (monability == PBAbilities::PRIMORDIALSEA) || (monability == PBAbilities::DESOLATELAND) || (monability == PBAbilities::DELTASTREAM)
        monRoles.push(PBMonRoles::WEATHERSETTER)
      end
      if fieldmove || (monability == PBAbilities::GRASSYSURGE) || (monability == PBAbilities::ELECTRICSURGE) || (monability == PBAbilities::MISTYSURGE) || (monability == PBAbilities::PSYCHICSURGE) || mon.item==(PBItems::AMPLIFIELDROCK)
        monRoles.push(PBMonRoles::FIELDSETTER)
      end
      if position==(party.length-1)
      #if $game_switches[525] && position==(party.length-1)
        monRoles.push(PBMonRoles::ACE)
      end
      secondhighest=true
      if party.length>2
        for i in 0..(party.length-2)
          next if party[i].nil?
          if mon.level<party[i].level
            secondhighest=false
          end
        end
      end
      #if $game_switches[525]&& secondhighest
      if secondhighest
        monRoles.push(PBMonRoles::SECOND)
      end
      #PBDebug.log(sprintf("Ending role assignment for %s",PBSpecies.getName(mon.species))) if $INTERNAL
      #PBDebug.log(sprintf("")) if $INTERNAL
      return monRoles
    end
    #PBDebug.log(sprintf("Ending role assignment for %s",PBSpecies.getName(mon.species))) if $INTERNAL
    #PBDebug.log(sprintf("")) if $INTERNAL
    return monRoles
  end

  def getAbilityDisruptScore(move,attacker,opponent,skill)
    abilityscore=100.0
    return abilityscore if !opponent.abilitynulled == false #if the ability doesn't work, then nothing here matters
    if opponent.ability == PBAbilities::SPEEDBOOST
      PBDebug.log(sprintf("Speedboost Disrupt")) if $INTERNAL
      abilityscore*=1.1
      if opponent.stages[PBStats::SPEED]<2
        abilityscore*=1.3
      end
    elsif opponent.ability == PBAbilities::SANDVEIL
      PBDebug.log(sprintf("Sand veil Disrupt")) if $INTERNAL
      if @weather==PBWeather::SANDSTORM
        abilityscore*=1.3
      end
    elsif opponent.ability == PBAbilities::VOLTABSORB || opponent.ability == PBAbilities::LIGHTNINGROD || opponent.ability == PBAbilities::MOTORDRIVE
      PBDebug.log(sprintf("Volt Absorb Disrupt")) if $INTERNAL
      elecvar = false
      totalelec=true
      elecmove=nil
      for i in attacker.moves
        if !(i.type == PBTypes::ELECTRIC)
          totalelec=false
        end
        if (i.type == PBTypes::ELECTRIC)
          elecvar=true
          elecmove=i
        end
      end
      if elecvar
        if totalelec
          abilityscore*=3
        end
        if pbTypeModNoMessages(elecmove.type,attacker,opponent,elecmove,skill)>4
          abilityscore*=2
        end
      end
    elsif opponent.ability == PBAbilities::WATERABSORB || opponent.ability == PBAbilities::STORMDRAIN || opponent.ability == PBAbilities::DRYSKIN
      PBDebug.log(sprintf("Water Absorb Disrupt")) if $INTERNAL
      watervar = false
      totalwater=true
      watermove=nil
      firevar=false
      for i in attacker.moves
        if !(i.type == PBTypes::WATER)
          totalwater=false
        end
        if (i.type == PBTypes::WATER)
          watervar=true
          watermove=i
        end
        if (i.type == PBTypes::FIRE)
          firevar=true
        end
      end
      if watervar
        if totalwater
          abilityscore*=3
        end
        if pbTypeModNoMessages(watermove.type,attacker,opponent,watermove,skill)>4
          abilityscore*=2
        end
      end
      if opponent.ability == PBAbilities::DRYSKIN
        if firevar
          abilityscore*=0.5
        end
      end
    elsif opponent.ability == PBAbilities::FLASHFIRE
      PBDebug.log(sprintf("Flash Fire Disrupt")) if $INTERNAL
      firevar = false
      totalfire=true
      firemove=nil
      for i in attacker.moves
        if !(i.type == PBTypes::FIRE)
          totalfire=false
        end
        if (i.type == PBTypes::FIRE)
          firevar=true
          firemove=i
        end
      end
      if firevar
        if totalfire
          abilityscore*=3
        end
        if pbTypeModNoMessages(firemove.type,attacker,opponent,firemove,skill)>4
          abilityscore*=2
        end
      end
    elsif opponent.ability == PBAbilities::LEVITATE
      PBDebug.log(sprintf("Levitate Disrupt")) if $INTERNAL
      groundvar = false
      totalground=true
      groundmove=nil
      for i in attacker.moves
        if !(i.type == PBTypes::GROUND)
          totalground=false
        end
        if (i.type == PBTypes::GROUND)
          groundvar=true
          groundmove=i
        end
      end
      if groundvar
        if totalground
          abilityscore*=3
        end
        if pbTypeModNoMessages(groundmove.type,attacker,opponent,groundmove,skill)>4
          abilityscore*=2
        end
      end
    elsif opponent.ability == PBAbilities::SHADOWTAG
      PBDebug.log(sprintf("Shadow Tag Disrupt")) if $INTERNAL
      if !attacker.hasType?(PBTypes::GHOST)
        abilityscore*=1.5
      end
    elsif opponent.ability == PBAbilities::ARENATRAP
      PBDebug.log(sprintf("Arena Trap Disrupt")) if $INTERNAL
      if attacker.isAirborne?
        abilityscore*=1.5
      end
    elsif opponent.ability == PBAbilities::WONDERGUARD
      PBDebug.log(sprintf("Wonder Guard Disrupt")) if $INTERNAL
      wondervar=false
      for i in attacker.moves
        if pbTypeModNoMessages(i.type,attacker,opponent,i,skill)>4
          wondervar=true
        end
      end
      if !wondervar
        abilityscore*=5
      end
    elsif opponent.ability == PBAbilities::SERENEGRACE
      PBDebug.log(sprintf("Serene Grace Disrupt")) if $INTERNAL
      abilityscore*=1.3
    elsif opponent.ability == PBAbilities::PUREPOWER || opponent.ability == PBAbilities::HUGEPOWER
      PBDebug.log(sprintf("Pure Power Disrupt")) if $INTERNAL
      abilityscore*=2
    elsif opponent.ability == PBAbilities::SOUNDPROOF
      PBDebug.log(sprintf("Soundproof Disrupt")) if $INTERNAL
      soundvar=false
      for i in attacker.moves
        if i.isSoundBased?
          soundvar=true
        end
      end
      if !soundvar
        abilityscore*=3
      end
    elsif opponent.ability == PBAbilities::THICKFAT
      PBDebug.log(sprintf("Thick Fat Disrupt")) if $INTERNAL
      totalguard=true
      for i in attacker.moves
        if !(i.type == PBTypes::FIRE) && !(i.type == PBTypes::ICE)
          totalguard=false
        end
      end
      if totalguard
        abilityscore*=1.5
      end
    elsif opponent.ability == PBAbilities::TRUANT
      PBDebug.log(sprintf("Truant Disrupt")) if $INTERNAL
      abilityscore*=0.1
    elsif opponent.ability == PBAbilities::GUTS || opponent.ability == PBAbilities::QUICKFEET || opponent.ability == PBAbilities::MARVELSCALE
      PBDebug.log(sprintf("Guts Disrupt")) if $INTERNAL
      if opponent.status!=0
        abilityscore*=1.5
      end
    elsif opponent.ability == PBAbilities::LIQUIDOOZE
      PBDebug.log(sprintf("Liquid Ooze Disrupt")) if $INTERNAL
      if opponent.effects[PBEffects::LeechSeed]>=0 || attacker.pbHasMove?((PBMoves::LEECHSEED))
        abilityscore*=2
      end
    elsif opponent.ability == PBAbilities::AIRLOCK || opponent.ability == PBAbilities::CLOUDNINE
      PBDebug.log(sprintf("Airlock Disrupt")) if $INTERNAL
      abilityscore*=1.1
    elsif opponent.ability == PBAbilities::HYDRATION
      PBDebug.log(sprintf("Hydration Disrupt")) if $INTERNAL
      if @weather==PBWeather::RAINDANCE
        abilityscore*=1.3
      end
    elsif opponent.ability == PBAbilities::ADAPTABILITY
      PBDebug.log(sprintf("Adaptability Disrupt")) if $INTERNAL
      abilityscore*=1.3
    elsif opponent.ability == PBAbilities::SKILLLINK
      PBDebug.log(sprintf("Skill Link Disrupt")) if $INTERNAL
      abilityscore*=1.5
    elsif opponent.ability == PBAbilities::POISONHEAL
      PBDebug.log(sprintf("Poison Heal Disrupt")) if $INTERNAL
      if opponent.status==PBStatuses::POISON
        abilityscore*=2
      end
    elsif opponent.ability == PBAbilities::NORMALIZE
      PBDebug.log(sprintf("Normalize Disrupt")) if $INTERNAL
      abilityscore*=0.6
    elsif opponent.ability == PBAbilities::MAGICGUARD
      PBDebug.log(sprintf("Magic Guard Disrupt")) if $INTERNAL
      abilityscore*=1.4
    elsif opponent.ability == PBAbilities::STALL
      PBDebug.log(sprintf("Stall Disrupt")) if $INTERNAL
      abilityscore*=0.5
    elsif opponent.ability == PBAbilities::TECHNICIAN
      PBDebug.log(sprintf("Technician Disrupt")) if $INTERNAL
      abilityscore*=1.3
    elsif opponent.ability == PBAbilities::MOLDBREAKER
      PBDebug.log(sprintf("Mold Breaker Disrupt")) if $INTERNAL
      abilityscore*=1.1
    elsif opponent.ability == PBAbilities::UNAWARE
      PBDebug.log(sprintf("Unaware Disrupt")) if $INTERNAL
      abilityscore*=1.7
    elsif opponent.ability == PBAbilities::SLOWSTART
      PBDebug.log(sprintf("Slow Start Disrupt")) if $INTERNAL
      abilityscore*=0.3
    elsif opponent.ability == PBAbilities::MULTITYPE || opponent.ability == PBAbilities::STANCECHANGE || opponent.ability == PBAbilities::SCHOOLING || opponent.ability == PBAbilities::SHIELDSDOWN || opponent.ability == PBAbilities::DISGUISE || opponent.ability == PBAbilities::RKSSYSTEM || opponent.ability == PBAbilities::POWERCONSTRUCT
      PBDebug.log(sprintf("Multitype Disrupt")) if $INTERNAL
      abilityscore*=0
    elsif opponent.ability == PBAbilities::SHEERFORCE
      PBDebug.log(sprintf("Sheer Force Disrupt")) if $INTERNAL
      abilityscore*=1.2
    elsif opponent.ability == PBAbilities::CONTRARY
      PBDebug.log(sprintf("Contrary Disrupt")) if $INTERNAL
      abilityscore*=1.4
      if opponent.stages[PBStats::ATTACK]>0 || opponent.stages[PBStats::SPATK]>0 || opponent.stages[PBStats::DEFENSE]>0 || opponent.stages[PBStats::SPDEF]>0 || opponent.stages[PBStats::SPEED]>0
        abilityscore*=2
      end
    elsif opponent.ability == PBAbilities::DEFEATIST
      PBDebug.log(sprintf("Defeatist Disrupt")) if $INTERNAL
      abilityscore*=0.5
    elsif opponent.ability == PBAbilities::MULTISCALE
      PBDebug.log(sprintf("Multiscale Disrupt")) if $INTERNAL
      if opponent.hp==opponent.totalhp
        abilityscore*=1.5
      end
    elsif opponent.ability == PBAbilities::HARVEST
      PBDebug.log(sprintf("Harvest Disrupt")) if $INTERNAL
      abilityscore*=1.2
    elsif opponent.ability == PBAbilities::MOODY
      PBDebug.log(sprintf("Moody Disrupt")) if $INTERNAL
      abilityscore*=1.8
    elsif opponent.ability == PBAbilities::SAPSIPPER
      PBDebug.log(sprintf("Sap Sipper Disrupt")) if $INTERNAL
      grassvar = false
      totalgrass=true
      grassmove=nil
      for i in attacker.moves
        if !(i.type == PBTypes::GRASS)
          totalgrass=false
        end
        if (i.type == PBTypes::GRASS)
          grassvar=true
          grassmove=i
        end
      end
      if grassvar
        if totalgrass
          abilityscore*=3
        end
        if pbTypeModNoMessages(grassmove.type,attacker,opponent,grassmove,skill)>4
          abilityscore*=2
        end
      end
    elsif opponent.ability == PBAbilities::PRANKSTER
      PBDebug.log(sprintf("Prankster Disrupt")) if $INTERNAL
      if attacker.speed>opponent.speed
        abilityscore*=1.5
      end
    elsif opponent.ability == PBAbilities::SNOWCLOAK
      PBDebug.log(sprintf("Snow Cloak Disrupt")) if $INTERNAL
      if @weather==PBWeather::HAIL
        abilityscore*=1.1
      end
    elsif opponent.ability == PBAbilities::FURCOAT
      PBDebug.log(sprintf("Fur Coat Disrupt")) if $INTERNAL
      if attacker.attack>attacker.spatk
        abilityscore*=1.5
      end
    elsif opponent.ability == PBAbilities::PARENTALBOND
      PBDebug.log(sprintf("Parental Bond Disrupt")) if $INTERNAL
      abilityscore*=3
    elsif opponent.ability == PBAbilities::PROTEAN
      PBDebug.log(sprintf("Protean Disrupt")) if $INTERNAL
      abilityscore*=3
    elsif opponent.ability == PBAbilities::TOUGHCLAWS
      PBDebug.log(sprintf("Tough Claws Disrupt")) if $INTERNAL
      abilityscore*=1.2
    elsif opponent.ability == PBAbilities::BEASTBOOST
      PBDebug.log(sprintf("Beast Boost Disrupt")) if $INTERNAL
      abilityscore*=1.1
    elsif opponent.ability == PBAbilities::COMATOSE
      PBDebug.log(sprintf("Comatose Disrupt")) if $INTERNAL
      abilityscore*=1.3
    elsif opponent.ability == PBAbilities::FLUFFY
      PBDebug.log(sprintf("Fluffy Disrupt")) if $INTERNAL
      abilityscore*=1.5
      firevar = false
      for i in attacker.moves
        if (i.type == PBTypes::FIRE)
          firevar=true
        end
      end
      if firevar
        abilityscore*=0.5
      end
    elsif opponent.ability == PBAbilities::MERCILESS
      PBDebug.log(sprintf("Merciless Disrupt")) if $INTERNAL
      abilityscore*=1.3
    elsif opponent.ability == PBAbilities::WATERBUBBLE
      PBDebug.log(sprintf("Water Bubble Disrupt")) if $INTERNAL
      abilityscore*=1.5
      firevar = false
      for i in attacker.moves
        if (i.type == PBTypes::FIRE)
          firevar=true
        end
      end
      if firevar
        abilityscore*=1.3
      end
    elsif attacker.pbPartner==opponent
      if abilityscore!=0
        if abilityscore>200
          abilityscore=200
        end
        tempscore = abilityscore
        abilityscore = 200 - tempscore
      end
    end
    abilityscore*=0.01
    return abilityscore
  end

  def getFieldDisruptScore(attacker,opponent,skill)
    fieldscore=100.0
    aroles = pbGetMonRole(attacker,opponent,skill)
    oroles = pbGetMonRole(opponent,attacker,skill)
    aimem = getAIMemory(skill,opponent.pokemonIndex)
    if $fefieldeffect==1 # Electric Terrain
      PBDebug.log(sprintf("Electric Terrain Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:ELECTRIC) || opponent.pbPartner.pbHasType?(:ELECTRIC)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:ELECTRIC)
        fieldscore*=0.5
      end
      partyelec=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:ELECTRIC)
          partyelec=true
        end
      end
      if partyelec
        fieldscore*=0.5
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::SURGESURFER)
        fieldscore*=1.3
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::SURGESURFER)
        fieldscore*=0.7
      end
    end
    if $fefieldeffect==2 # Grassy Terrain
      PBDebug.log(sprintf("Grassy Terrain Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:GRASS) || opponent.pbPartner.pbHasType?(:GRASS)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:GRASS)
        fieldscore*=0.5
      end
      if opponent.pbHasType?(:FIRE) || opponent.pbPartner.pbHasType?(:FIRE)
        fieldscore*=1.8
      end
      if attacker.pbHasType?(:FIRE)
        fieldscore*=0.2
      end
      partygrass=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:GRASS)
          partygrass=true
        end
      end
      if partygrass
        fieldscore*=0.5
      end
      partyfire=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:FIRE)
          partyfire=true
        end
      end
      if partyfire
        fieldscore*=0.2
      end
      if aroles.include?(PBMonRoles::SPECIALWALL) || aroles.include?(PBMonRoles::PHYSICALWALL)
        fieldscore*=0.8
      end
      if oroles.include?(PBMonRoles::SPECIALWALL) || oroles.include?(PBMonRoles::PHYSICALWALL)
        fieldscore*=1.2
      end
    end
    if $fefieldeffect==3 # Misty Terrain
      PBDebug.log(sprintf("Misty Terrain Disrupt")) if $INTERNAL
      if attacker.spatk>attacker.attack
        if opponent.pbHasType?(:FAIRY) || opponent.pbPartner.pbHasType?(:FAIRY)
          fieldscore*=1.3
        end
      end
      if opponent.spatk>opponent.attack
        if attacker.pbHasType?(:FAIRY)
          fieldscore*=0.7
        end
      end
      if opponent.pbHasType?(:DRAGON) || opponent.pbPartner.pbHasType?(:DRAGON)
        fieldscore*=0.5
      end
      if attacker.pbHasType?(:DRAGON)
        fieldscore*=1.5
      end
      partyfairy=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:FAIRY)
          partyfairy=true
        end
      end
      if partyfairy
        fieldscore*=0.7
      end
      partydragon=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:DRAGON)
          partydragon=true
        end
      end
      if partydragon
        fieldscore*=1.5
      end
      if !(attacker.pbHasType?(:POISON) || attacker.pbHasType?(:STEEL))
        if $fecounter==1
          fieldscore*=1.8
        end
      end
    end
    if $fefieldeffect==4 # Dark Crystal Cavern
      PBDebug.log(sprintf("Dark Crystal Cavern Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:DARK) || opponent.pbPartner.pbHasType?(:DARK) ||
         opponent.pbHasType?(:GHOST) || opponent.pbPartner.pbHasType?(:GHOST)
        fieldscore*=1.3
      end
      if attacker.pbHasType?(:DARK) || attacker.pbHasType?(:GHOST)
        fieldscore*=0.7
      end
      partyspook=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:DARK) || k.hasType?(:GHOST)
          partyspook=true
        end
      end
      if partyspook
        fieldscore*=0.7
      end
    end
    if $fefieldeffect==5 # Chess field
      PBDebug.log(sprintf("Chess Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:PSYCHIC) || opponent.pbPartner.pbHasType?(:PSYCHIC)
        fieldscore*=1.3
      end
      if attacker.pbHasType?(:PSYCHIC)
        fieldscore*=0.7
      end
      partypsy=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:PSYCHIC)
          partypsy=true
        end
      end
      if partypsy
        fieldscore*=0.7
      end
      if attacker.speed>opponent.speed
        fieldscore*=1.3
      else
        fieldscore*=0.7
      end
    end
    if $fefieldeffect==6 # Big Top field
      PBDebug.log(sprintf("Big Top Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:FIGHTING) || opponent.pbPartner.pbHasType?(:FIGHTING)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:FIGHTING)
        fieldscore*=0.5
      end
      partyfight=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:FIGHTING)
          partyfight=true
        end
      end
      if partyfight
        fieldscore*=0.5
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::DANCER)
        fieldscore*=1.5
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::DANCER)
        fieldscore*=0.5
      end
      if attacker.pbHasMove?((PBMoves::SING)) ||
          attacker.pbHasMove?((PBMoves::DRAGONDANCE)) ||
          attacker.pbHasMove?((PBMoves::QUIVERDANCE))
        fieldscore*=0.5
      end
      fieldscore*=1.5 if checkAImoves([PBMoves::SING,PBMoves::DRAGONDANCE,PBMoves::QUIVERDANCE],aimem)
    end
    if $fefieldeffect==7 # Burning Field
      PBDebug.log(sprintf("Burning Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:FIRE) || opponent.pbPartner.pbHasType?(:FIRE)
        fieldscore*=1.8
      end
      if attacker.pbHasType?(:FIRE)
        fieldscore*=0.3
      else
        fieldscore*=1.5
        if attacker.pbHasType?(:GRASS) || attacker.pbHasType?(:ICE) || attacker.pbHasType?(:BUG) || attacker.pbHasType?(:STEEL)
          fieldscore*=1.8
        end
      end
      partyfire=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:FIRE)
          partyfire=true
        end
      end
      if partyfire
        fieldscore*=0.7
      end
      partyflamm=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:GRASS) || k.hasType?(:ICE) || k.hasType?(:BUG) || k.hasType?(:STEEL)
          partyflamm=true
        end
      end
      if partyflamm
        fieldscore*=1.5
      end
    end
    if $fefieldeffect==8 # Swamp field
      PBDebug.log(sprintf("Swamp Field Disrupt")) if $INTERNAL
      if attacker.pbHasMove?((PBMoves::SLEEPPOWDER))
        fieldscore*=0.7
      end
      fieldscore*=1.3 if checkAImoves([PBMoves::SLEEPPOWDER],aimem)
    end
    if $fefieldeffect==9 # Rainbow field
      PBDebug.log(sprintf("Rainbow Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:NORMAL) || opponent.pbPartner.pbHasType?(:NORMAL)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:NORMAL)
        fieldscore*=0.5
      end
      partynorm=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:NORMAL)
          partynorm=true
        end
      end
      if partynorm
        fieldscore*=0.5
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::CLOUDNINE)
        fieldscore*=1.4
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::CLOUDNINE)
        fieldscore*=0.6
      end
      if attacker.pbHasMove?((PBMoves::SONICBOOM))
        fieldscore*=0.8
      end
      fieldscore*=1.2 if checkAImoves([PBMoves::SONICBOOM],aimem)
    end
    if $fefieldeffect==10 # Corrosive field
      PBDebug.log(sprintf("Corrosive Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:POISON) || opponent.pbPartner.pbHasType?(:POISON)
        fieldscore*=1.3
      end
      if attacker.pbHasType?(:POISON)
        fieldscore*=0.7
      end
      partypoison=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:POISON)
          partypoison=true
        end
      end
      if partypoison
        fieldscore*=0.7
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::CORROSION)
        fieldscore*=1.5
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::CORROSION)
        fieldscore*=0.5
      end
      if attacker.pbHasMove?((PBMoves::SLEEPPOWDER))
        fieldscore*=0.7
      end
      fieldscore*=1.3 if checkAImoves([PBMoves::SLEEPPOWDER],aimem)
    end
    if $fefieldeffect==11 # Corromist field
      PBDebug.log(sprintf("Corrosive Mist Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:POISON) || opponent.pbPartner.pbHasType?(:POISON)
        fieldscore*=1.3
      end
      if attacker.pbHasType?(:POISON)
        fieldscore*=0.7
      else
        if !attacker.pbHasType?(:STEEL)
          fieldscore*=1.4
        end
      end
      nopartypoison=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if !(k.hasType?(:POISON))
          nopartypoison=true
        end
      end
      if nopartypoison
        fieldscore*=1.4
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::CORROSION)
        fieldscore*=1.5
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::CORROSION)
        fieldscore*=0.5
      end
      if opponent.pbHasType?(:FIRE) || opponent.pbPartner.pbHasType?(:FIRE)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:FIRE)
        fieldscore*=0.8
      end
      partyfire=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:FIRE)
          partyfire=true
        end
      end
      if partyfire
        fieldscore*=0.8
      end
    end
    if $fefieldeffect==12 # Desert field
      PBDebug.log(sprintf("Desert Field Disrupt")) if $INTERNAL
      if attacker.spatk > attacker.attack
        if opponent.pbHasType?(:GROUND) || opponent.pbPartner.pbHasType?(:GROUND)
          fieldscore*=1.3
        end
      end
      if opponent.spatk > opponent.attack
        if attacker.pbHasType?(:GROUND)
          fieldscore*=0.7
        end
      end
      if attacker.pbHasType?(:ELECTRIC) || attacker.pbHasType?(:WATER)
        fieldscore*=1.5
      end
      if opponent.pbHasType?(:ELECTRIC) || opponent.pbPartner.pbHasType?(:WATER)
        fieldscore*=0.5
      end
      partyground=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:GROUND)
          partyground=true
        end
      end
      if partyground
        fieldscore*=0.7
      end
      partyweak=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:ELECTRIC) || k.hasType?(:WATER)
          partyweak=true
        end
      end
      if partyweak
        fieldscore*=1.5
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::SANDRUSH) && @weather!=PBWeather::SANDSTORM
        fieldscore*=1.3
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::SANDRUSH) && @weather!=PBWeather::SANDSTORM
        fieldscore*=0.7
      end
    end
    if $fefieldeffect==13 # Icy field
      PBDebug.log(sprintf("Icy Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:ICE) || opponent.pbPartner.pbHasType?(:ICE)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:ICE)
        fieldscore*=0.5
      end
      partyice=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:ICE)
          partyice=true
        end
      end
      if partyice
        fieldscore*=0.5
      end
      if opponent.pbHasType?(:FIRE) || opponent.pbPartner.pbHasType?(:FIRE)
        fieldscore*=0.5
      end
      if attacker.pbHasType?(:FIRE)
        fieldscore*=1.5
      end
      partyfire=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:FIRE)
          partyfire=true
        end
      end
      if partyfire
        fieldscore*=1.5
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::SLUSHRUSH) && @weather!=PBWeather::HAIL
        fieldscore*=1.3
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::SLUSHRUSH) && @weather!=PBWeather::HAIL
        fieldscore*=0.7
      end
    end
    if $fefieldeffect==14 # Rocky field
      PBDebug.log(sprintf("Rocky Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:ROCK) || opponent.pbPartner.pbHasType?(:ROCK)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:ROCK)
        fieldscore*=0.5
      end
      partyrock=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:ROCK)
          partyrock=true
        end
      end
      if partyrock
        fieldscore*=0.5
      end
    end
    if $fefieldeffect==15 # Forest field
      PBDebug.log(sprintf("Forest Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:GRASS) || opponent.pbHasType?(:BUG) || opponent.pbPartner.pbHasType?(:GRASS) || opponent.pbPartner.pbHasType?(:BUG)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:GRASS) || attacker.pbHasType?(:BUG)
        fieldscore*=0.5
      end
      partygrowth=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:GRASS) || k.hasType?(:BUG)
          partygrowth=true
        end
      end
      if partygrowth
        fieldscore*=0.5
      end
      if opponent.pbHasType?(:FIRE) || opponent.pbPartner.pbHasType?(:FIRE)
        fieldscore*=1.8
      end
      if attacker.pbHasType?(:FIRE)
        fieldscore*=0.2
      end
      partyfire=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:FIRE)
          partyfire=true
        end
      end
      if partyfire
        fieldscore*=0.2
      end
    end
    if $fefieldeffect==16 # Superheated field
      PBDebug.log(sprintf("Superheated Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:FIRE) || opponent.pbPartner.pbHasType?(:FIRE)
        fieldscore*=1.8
      end
      if attacker.pbHasType?(:FIRE)
        fieldscore*=0.2
      end
      partyfire=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:FIRE)
          partyfire=true
        end
      end
      if partyfire
        fieldscore*=0.2
      end
      if opponent.pbHasType?(:ICE) || opponent.pbPartner.pbHasType?(:ICE)
        fieldscore*=0.5
      end
      if attacker.pbHasType?(:ICE)
        fieldscore*=1.5
      end
      partyice=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:ICE)
          partyice=true
        end
      end
      if partyice
        fieldscore*=1.5
      end
      if opponent.pbHasType?(:WATER) || opponent.pbPartner.pbHasType?(:WATER)
        fieldscore*=0.8
      end
      if attacker.pbHasType?(:WATER)
        fieldscore*=1.2
      end
      partywater=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:WATER)
          partywater=true
        end
      end
      if partywater
        fieldscore*=1.2
      end
    end
    if $fefieldeffect==17 # Factory field
      PBDebug.log(sprintf("Factory Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:ELECTRIC) || opponent.pbPartner.pbHasType?(:ELECTRIC)
        fieldscore*=1.2
      end
      if attacker.pbHasType?(:ELECTRIC)
        fieldscore*=0.8
      end
      partyelec=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:ELECTRIC)
          partyelec=true
        end
      end
      if partyelec
        fieldscore*=0.8
      end
    end
    if $fefieldeffect==18 # Short-Circuit field
      PBDebug.log(sprintf("Short-Circuit Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:ELECTRIC) || opponent.pbPartner.pbHasType?(:ELECTRIC)
        fieldscore*=1.4
      end
      if attacker.pbHasType?(:ELECTRIC)
        fieldscore*=0.6
      end
      partyelec=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:ELECTRIC)
          partyelec=true
        end
      end
      if partyelec
        fieldscore*=0.6
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::SURGESURFER)
        fieldscore*=1.3
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::SURGESURFER)
        fieldscore*=0.7
      end
      if opponent.pbHasType?(:DARK) || opponent.pbPartner.pbHasType?(:DARK) ||
         opponent.pbHasType?(:GHOST) || opponent.pbPartner.pbHasType?(:GHOST)
        fieldscore*=1.3
      end
      if attacker.pbHasType?(:DARK) || attacker.pbHasType?(:GHOST)
        fieldscore*=0.7
      end
      partyspook=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:DARK) || k.hasType?(:GHOST)
          partyspook=true
        end
      end
      if partyspook
        fieldscore*=0.7
      end
    end
    if $fefieldeffect==19 # Wasteland field
      PBDebug.log(sprintf("Wasteland Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:POISON) || opponent.pbPartner.pbHasType?(:POISON)
        fieldscore*=1.3
      end
      if attacker.pbHasType?(:POISON)
        fieldscore*=0.7
      end
      partypoison=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:POISON)
          partypoison=true
        end
      end
      if partypoison
        fieldscore*=0.7
      end
    end
    if $fefieldeffect==20 # Ashen Beach field
      PBDebug.log(sprintf("Ashen Beach Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:FIGHTING) || opponent.pbPartner.pbHasType?(:FIGHTING) || opponent.pbHasType?(:PSYCHIC) || opponent.pbPartner.pbHasType?(:PSYCHIC)
        fieldscore*=1.3
      end
      if attacker.pbHasType?(:FIGHTING) || attacker.pbHasType?(:PSYCHIC)
        fieldscore*=0.7
      end
      partyfocus=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:FIGHTING) || k.hasType?(:PSYCHIC)
          partyfocus=true
        end
      end
      if partyfocus
        fieldscore*=0.7
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::SANDRUSH) && @weather!=PBWeather::SANDSTORM
        fieldscore*=1.3
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::SANDRUSH) && @weather!=PBWeather::SANDSTORM
        fieldscore*=0.7
      end
    end
    if $fefieldeffect==21 # Water Surface field
      PBDebug.log(sprintf("Water Surface Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:WATER) || opponent.pbPartner.pbHasType?(:WATER)
        fieldscore*=1.6
      end
      if attacker.pbHasType?(:WATER)
        fieldscore*=0.4
      else
        if !attacker.isAirborne?
          fieldscore*=1.3
        end
      end
      partywater=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:WATER)
          partywater=true
        end
      end
      if partywater
        fieldscore*=0.4
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::SWIFTSWIM) && @weather!=PBWeather::RAINDANCE
        fieldscore*=1.3
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::SWIFTSWIM) && @weather!=PBWeather::RAINDANCE
        fieldscore*=0.7
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::SURGESURFER)
        fieldscore*=1.3
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::SURGESURFER)
        fieldscore*=0.7
      end
      if !attacker.pbHasType?(:POISON) && $fecounter==1
        fieldscore*=1.3
      end
    end
    if $fefieldeffect==22 # Underwater field
      PBDebug.log(sprintf("Underwater Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:WATER) || opponent.pbPartner.pbHasType?(:WATER)
        fieldscore*=2
      end
      if attacker.pbHasType?(:WATER)
        fieldscore*=0.1
      else
        fieldscore*=1.5
        if attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:GROUND)
          fieldscore*=2
        end
      end
      if attacker.attack > attacker.spatk
        fieldscore*=1.2
      end
      if opponent.attack > opponent.spatk
        fieldscore*=0.8
      end
      partywater=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:WATER)
          partywater=true
        end
      end
      if partywater
        fieldscore*=0.1
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::SWIFTSWIM)
        fieldscore*=0.9
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::SWIFTSWIM)
        fieldscore*=1.1
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::SURGESURFER)
        fieldscore*=1.1
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::SURGESURFER)
        fieldscore*=0.9
      end
      if !attacker.pbHasType?(:POISON) && $fecounter==1
        fieldscore*=1.3
      end
    end
    if $fefieldeffect==23 # Cave field
      PBDebug.log(sprintf("Cave Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:ROCK) || opponent.pbPartner.pbHasType?(:ROCK)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:ROCK)
        fieldscore*=0.5
      end
      partyrock=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:ROCK)
          partyrock=true
        end
      end
      if partyrock
        fieldscore*=0.5
      end
      if opponent.pbHasType?(:GROUND) || opponent.pbPartner.pbHasType?(:GROUND)
        fieldscore*=1.2
      end
      if attacker.pbHasType?(:GROUND)
        fieldscore*=0.8
      end
      partyground=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:GROUND)
          partyground=true
        end
      end
      if partyground
        fieldscore*=0.8
      end
      if opponent.pbHasType?(:FLYING) || opponent.pbPartner.pbHasType?(:FLYING)
        fieldscore*=0.7
      end
      if attacker.pbHasType?(:FLYING)
        fieldscore*=1.3
      end
      partyflying=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:FLYING)
          partyflying=true
        end
      end
      if partyflying
        fieldscore*=1.3
      end
    end
    if $fefieldeffect==24 # Glitch field
      PBDebug.log(sprintf("Glitch Field Disrupt")) if $INTERNAL
      if attacker.pbHasType?(:DARK) || attacker.pbHasType?(:STEEL) || attacker.pbHasType?(:FAIRY)
        fieldscore*=1.3
      end
      partynew=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:DARK) || k.hasType?(:STEEL) || k.hasType?(:FAIRY)
          partynew=true
        end
      end
      if partynew
        fieldscore*=1.3
      end
      ratio1 = attacker.spatk/attacker.spdef.to_f
      ratio2 = attacker.spdef/attacker.spatk.to_f
      if ratio1 < 1
        fieldscore*=ratio1
      elsif ratio2 < 1
        fieldscore*=ratio2
      end
      oratio1 = opponent.spatk/attacker.spdef.to_f
      oratio2 = opponent.spdef/attacker.spatk.to_f
      if oratio1 > 1
        fieldscore*=oratio1
      elsif oratio2 > 1
        fieldscore*=oratio2
      end
    end
    if $fefieldeffect==25 # Crystal Cavern field
      PBDebug.log(sprintf("Crystal Cavern Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:ROCK) || opponent.pbPartner.pbHasType?(:ROCK) || opponent.pbHasType?(:DRAGON) || opponent.pbPartner.pbHasType?(:DRAGON)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:DRAGON)
        fieldscore*=0.5
      end
      partycryst=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:ROCK) || k.hasType?(:DRAGON)
          partycryst=true
        end
      end
      if partycryst
        fieldscore*=0.5
      end
    end
    if $fefieldeffect==26 # Murkwater Surface field
      PBDebug.log(sprintf("Murkwater Surface Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:WATER) || opponent.pbPartner.pbHasType?(:WATER)
        fieldscore*=1.6
      end
      if attacker.pbHasType?(:WATER)
        fieldscore*=0.4
      else
        if !attacker.isAirborne?
          fieldscore*=1.3
        end
      end
      partywater=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:WATER)
          partywater=true
        end
      end
      if partywater
        fieldscore*=0.4
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::SWIFTSWIM) && @weather!=PBWeather::RAINDANCE
        fieldscore*=1.3
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::SWIFTSWIM) && @weather!=PBWeather::RAINDANCE
        fieldscore*=0.7
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::SURGESURFER)
        fieldscore*=1.3
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::SURGESURFER)
        fieldscore*=0.7
      end
      if opponent.pbHasType?(:STEEL) || opponent.pbPartner.pbHasType?(:STEEL) || opponent.pbHasType?(:POISON) || opponent.pbPartner.pbHasType?(:POISON)
        fieldscore*=1.3
      end
      if attacker.pbHasType?(:POISON)
        fieldscore*=0.7
      else
        if !attacker.pbHasType?(:STEEL)
          fieldscore*=1.8
        end
      end
      partymurk=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:POISON)
          partymurk=true
        end
      end
      if partymurk
        fieldscore*=0.7
      end
    end
    if $fefieldeffect==27 # Mountain field
      PBDebug.log(sprintf("Mountain Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:ROCK) || opponent.pbPartner.pbHasType?(:ROCK) || opponent.pbHasType?(:FLYING) || opponent.pbPartner.pbHasType?(:FLYING)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:FLYING)
        fieldscore*=0.5
      end
      partymount=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:ROCK) || k.hasType?(:FLYING)
          partymount=true
        end
      end
      if partymount
        fieldscore*=0.5
      end
    end
    if $fefieldeffect==28 # Snowy Mountain field
      PBDebug.log(sprintf("Snowy Mountain Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:ROCK) || opponent.pbPartner.pbHasType?(:ROCK) || opponent.pbHasType?(:FLYING) || opponent.pbPartner.pbHasType?(:FLYING) || opponent.pbHasType?(:ICE) || opponent.pbPartner.pbHasType?(:ICE)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:ROCK) || attacker.pbHasType?(:FLYING) || attacker.pbHasType?(:ICE)
        fieldscore*=0.5
      end
      partymount=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:ROCK) || k.hasType?(:FLYING) || k.hasType?(:ICE)
          partymount=true
        end
      end
      if partymount
        fieldscore*=0.5
      end
      if opponent.pbHasType?(:FIRE) || opponent.pbPartner.pbHasType?(:FIRE)
        fieldscore*=0.5
      end
      if attacker.pbHasType?(:FIRE)
        fieldscore*=1.5
      end
      partyfire=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:FIRE)
          partyfire=true
        end
      end
      if partyfire
        fieldscore*=1.5
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::SLUSHRUSH) && @weather!=PBWeather::HAIL
        fieldscore*=1.3
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::SLUSHRUSH) && @weather!=PBWeather::HAIL
        fieldscore*=0.7
      end
    end
    if $fefieldeffect==29 # Holy field
      PBDebug.log(sprintf("Holy Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:NORMAL) || opponent.pbPartner.pbHasType?(:NORMAL) || opponent.pbHasType?(:FAIRY) || opponent.pbPartner.pbHasType?(:FAIRY)
        fieldscore*=1.4
      end
      if attacker.pbHasType?(:NORMAL) || attacker.pbHasType?(:FAIRY)
        fieldscore*=0.6
      end
      partynorm=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:NORMAL) || k.hasType?(:FAIRY)
          partynorm=true
        end
      end
      if partynorm
        fieldscore*=0.6
      end
      if opponent.pbHasType?(:DARK) || opponent.pbPartner.pbHasType?(:DARK) || opponent.pbHasType?(:GHOST) || opponent.pbPartner.pbHasType?(:GHOST)
        fieldscore*=0.5
      end
      if attacker.pbHasType?(:DARK) || attacker.pbHasType?(:GHOST)
        fieldscore*=1.5
      end
      partyspook=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:DARK) || k.hasType?(:GHOST)
          partyspook=true
        end
      end
      if partyspook
        fieldscore*=1.5
      end
      if opponent.pbHasType?(:DRAGON) || opponent.pbPartner.pbHasType?(:DRAGON) || opponent.pbHasType?(:PSYCHIC) || opponent.pbPartner.pbHasType?(:PSYCHIC)
        fieldscore*=1.2
      end
      if attacker.pbHasType?(:DRAGON) || attacker.pbHasType?(:PSYCHIC)
        fieldscore*=0.8
      end
      partymyst=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:DRAGON) || k.hasType?(:PSYCHIC)
          partymyst=true
        end
      end
      if partymyst
        fieldscore*=0.8
      end
    end
    if $fefieldeffect==30 # Mirror field
      PBDebug.log(sprintf("Mirror Field Disrupt")) if $INTERNAL
      if opponent.stages[PBStats::ACCURACY]!=0
        minimini = opponent.stages[PBStats::ACCURACY]
        minimini*=10.0
        minimini+=100
        minimini/=100
        fieldscore*=minimini
      end
      if opponent.stages[PBStats::EVASION]!=0
        minimini = opponent.stages[PBStats::EVASION]
        minimini*=10.0
        minimini+=100
        minimini/=100
        fieldscore*=minimini
      end
      if attacker.stages[PBStats::ACCURACY]!=0
        minimini = attacker.stages[PBStats::ACCURACY]
        minimini*=(-10.0)
        minimini+=100
        minimini/=100
        fieldscore*=minimini
      end
      if attacker.stages[PBStats::EVASION]!=0
        minimini = attacker.stages[PBStats::EVASION]
        minimini*=(-10.0)
        minimini+=100
        minimini/=100
        fieldscore*=minimini
      end
    end
    if $fefieldeffect==31 # Fairytale field
      PBDebug.log(sprintf("Fairytale Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:DRAGON) || opponent.pbPartner.pbHasType?(:DRAGON) || opponent.pbHasType?(:STEEL) || opponent.pbPartner.pbHasType?(:STEEL) || opponent.pbHasType?(:FAIRY) || opponent.pbPartner.pbHasType?(:FAIRY)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:DRAGON) || attacker.pbHasType?(:STEEL) || attacker.pbHasType?(:FAIRY)
        fieldscore*=0.5
      end
      partyfair=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:DRAGON) || k.hasType?(:STEEL) || k.hasType?(:FAIRY)
          partyfair=true
        end
      end
      if partyfair
        fieldscore*=0.5
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::STANCECHANGE)
        fieldscore*=1.3
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::STANCECHANGE)
        fieldscore*=0.7
      end
    end
    if $fefieldeffect==32 # Dragon's Den field
      PBDebug.log(sprintf("Dragon's Den Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:DRAGON) || opponent.pbPartner.pbHasType?(:DRAGON)
        fieldscore*=1.7
      end
      if attacker.pbHasType?(:DRAGON)
        fieldscore*=0.3
      end
      partydrago=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:DRAGON)
          partydrago=true
        end
      end
      if partydrago
        fieldscore*=0.3
      end
      if opponent.pbHasType?(:FIRE) || opponent.pbPartner.pbHasType?(:FIRE)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:FIRE)
        fieldscore*=0.5
      end
      partyfire=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:FIRE)
          partyfire=true
        end
      end
      if partyfire
        fieldscore*=0.5
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::MULTISCALE)
        fieldscore*=1.3
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::MULTISCALE)
        fieldscore*=0.7
      end
    end
    if $fefieldeffect==33 # Flower Garden field
      PBDebug.log(sprintf("Flower Garden Field Disrupt")) if $INTERNAL
      if $fecounter>2
        if opponent.pbHasType?(:BUG) || opponent.pbPartner.pbHasType?(:BUG) || opponent.pbHasType?(:GRASS) || opponent.pbPartner.pbHasType?(:GRASS)
          fieldscore*=(0.5*$fecounter)
        end
        if attacker.pbHasType?(:GRASS) || attacker.pbHasType?(:BUG)
          fieldscore*= (1.0/$fecounter)
        end
        partygrass=false
        for k in pbParty(attacker.index)
          next if k.nil?
          if k.hasType?(:BUG) || k.hasType?(:GRASS)
            partygrass=true
          end
        end
        if partygrass
          fieldscore*= (1.0/$fecounter)
        end
        if opponent.pbHasType?(:FIRE) || opponent.pbPartner.pbHasType?(:FIRE)
          fieldscore*=(0.4*$fecounter)
        end
        if attacker.pbHasType?(:FIRE)
          fieldscore*= (1.0/$fecounter)
        end
        partyfire=false
        for k in pbParty(attacker.index)
          next if k.nil?
          if k.hasType?(:FIRE)
            partyfire=true
          end
        end
        if partyfire
          fieldscore*= (1.0/$fecounter)
        end
      end
    end
    if $fefieldeffect==34 # Starlight Arena field
      PBDebug.log(sprintf("Starlight Arena Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:PSYCHIC) || opponent.pbPartner.pbHasType?(:PSYCHIC)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:PSYCHIC)
        fieldscore*=0.5
      end
      partypsy=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:PSYCHIC)
          partypsy=true
        end
      end
      if partypsy
        fieldscore*=0.5
      end
      if opponent.pbHasType?(:FAIRY) || opponent.pbPartner.pbHasType?(:FAIRY) || opponent.pbHasType?(:DARK) || opponent.pbPartner.pbHasType?(:DARK)
        fieldscore*=1.3
      end
      if attacker.pbHasType?(:FAIRY) || attacker.pbHasType?(:DARK)
        fieldscore*=0.7
      end
      partystar=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:FAIRY) || k.hasType?(:DARK)
          partystar=true
        end
      end
      if partystar
        fieldscore*=0.7
      end
    end
    if $fefieldeffect==35 # New World field
      PBDebug.log(sprintf("New World Field Disrupt")) if $INTERNAL
      fieldscore = 0
    end
    if $fefieldeffect==36 # Inverse field
      PBDebug.log(sprintf("Inverse Field Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:NORMAL) || opponent.pbPartner.pbHasType?(:NORMAL)
        fieldscore*=1.7
      end
      if attacker.pbHasType?(:NORMAL)
        fieldscore*=0.3
      end
      partynorm=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:NORMAL)
          partynorm=true
        end
      end
      if partynorm
        fieldscore*=0.3
      end
      if opponent.pbHasType?(:ICE) || opponent.pbPartner.pbHasType?(:ICE)
        fieldscore*=1.5
      end
      if attacker.pbHasType?(:ICE)
        fieldscore*=0.5
      end
      partyice=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:ICE)
          partyice=true
        end
      end
      if partyice
        fieldscore*=0.5
      end
    end
    if $fefieldeffect==37 # Psychic Terrain
      PBDebug.log(sprintf("Psychic Terrain Disrupt")) if $INTERNAL
      if opponent.pbHasType?(:PSYCHIC) || opponent.pbPartner.pbHasType?(:PSYCHIC)
        fieldscore*=1.7
      end
      if attacker.pbHasType?(:PSYCHIC)
        fieldscore*=0.3
      end
      partypsy=false
      for k in pbParty(attacker.index)
        next if k.nil?
        if k.hasType?(:PSYCHIC)
          partypsy=true
        end
      end
      if partypsy
        fieldscore*=0.3
      end
      if (!opponent.abilitynulled && opponent.ability == PBAbilities::TELEPATHY)
        fieldscore*=1.3
      end
      if (!attacker.abilitynulled && attacker.ability == PBAbilities::TELEPATHY)
        fieldscore*=0.7
      end
    end
    fieldscore*=0.01
    return fieldscore
  end

  def setupminiscore(attacker,opponent,skill,move,sweep,code,double,initialscores,scoreindex)
    aimem = getAIMemory(skill,opponent.pokemonIndex)
    miniscore=100
    if attacker.effects[PBEffects::Substitute]>0 || attacker.effects[PBEffects::Disguise]
      miniscore*=1.3
    end
    if initialscores.length>0
      miniscore*=1.3 if hasbadmoves(initialscores,scoreindex,20)
    end
    if (attacker.hp.to_f)/attacker.totalhp>0.75
      miniscore*=1.2 if sweep
      miniscore*=1.1 if !sweep
    end
    if (attacker.hp.to_f)/attacker.totalhp<0.33
      miniscore*=0.3
    end
    if (attacker.hp.to_f)/attacker.totalhp<0.75 && (!attacker.abilitynulled && (attacker.ability == PBAbilities::EMERGENCYEXIT || attacker.ability == PBAbilities::WIMPOUT) || (attacker.itemWorks? && attacker.item == PBItems::EJECTBUTTON))
      miniscore*=0.3
    end
    if attacker.pbOpposingSide.effects[PBEffects::Retaliate]
      miniscore*=0.3
    end
    if opponent.effects[PBEffects::HyperBeam]>0
      miniscore*=1.3 if sweep
      miniscore*=1.2 if !sweep
    end
    if opponent.effects[PBEffects::Yawn]>0
      miniscore*=1.7 if sweep
      miniscore*=1.3 if !sweep
    end
    if skill>=PBTrainerAI.mediumSkill
      if aimem.length > 0
        maxdam = checkAIdamage(aimem,attacker,opponent,skill)
        if maxdam<(attacker.hp/4.0) && sweep
          miniscore*=1.2
        elsif maxdam<(attacker.hp/3.0) && !sweep
          miniscore*=1.1
        elsif maxdam<(attacker.hp/4.0) && code == 10
          miniscore*=1.5
        else
          if move.basedamage==0
            miniscore*=0.8
            if maxdam>attacker.hp
              miniscore*=0.1
            end
          end
        end
      else
        if move.basedamage==0
          effcheck = PBTypes.getCombinedEffectiveness(opponent.type1,attacker.type1,attacker.type2)
          if effcheck > 4
            miniscore*=0.5
          end
          effcheck2 = PBTypes.getCombinedEffectiveness(opponent.type2,attacker.type1,attacker.type2)
          if effcheck2 > 4
            miniscore*=0.5
          end
        end
      end
    end
    #hi we are going in the comments for this one because it is in dire need of explanation
    #up until this point, most of the key differences between different set up moves has
    #been whether they are good for setting up to sweep or not.
    #this is not the case past here.
    #there are some really obnoxious differences between moves, and the way i'm dealing
    #with it is through binary strings.
    #this string is passed as a single number and is then processed by the function as such:
    # 00001 = attack    00010 = defense   00100 = sp.attack   01000 = sp.defense  10000 = speed
    #cosmic power would be  01010 in binary or 10 in normal, bulk up would be 00011 or 3, etc
    #evasion has a code of 0
    #this way new moves can be added and still use this function without any loss in
    #the overall scoring precision of the AI
    if attacker.turncount<2
      miniscore*=1.2 if sweep
      miniscore*=1.1 if !sweep
    end
    if opponent.status!=0
      miniscore*=1.2 if sweep
      miniscore*=1.1 if !sweep
    end
    if opponent.status==PBStatuses::SLEEP || opponent.status==PBStatuses::FROZEN
      miniscore*=1.3
    end
    if opponent.effects[PBEffects::Encore]>0
      if opponent.moves[(opponent.effects[PBEffects::EncoreIndex])].basedamage==0
        if sweep || code == 10 #cosmic power
          miniscore*=1.5
        else
          miniscore*=1.3
        end
      end
    end
    if attacker.effects[PBEffects::Confusion]>0
      if code & 0b1 == 0b1 #if move boosts attack
        miniscore*=0.2
        miniscore*=0.5 if double #using swords dance or shell smash while confused is Extra Bad
        miniscore*=1.5 if code & 0b11 == 0b11 #adds a correction for moves that boost attack and defense
      else
        miniscore*=0.5
      end
    end
    sweep = false if code == 3 #from here on out, bulk up is not a sweep move
    if attacker.effects[PBEffects::LeechSeed]>=0 || attacker.effects[PBEffects::Attract]>=0
      miniscore*=0.6 if sweep
      miniscore*=0.3 if !sweep
    end
    if !sweep
      miniscore*=0.2 if attacker.effects[PBEffects::Toxic]>0
      miniscore*=1.1 if opponent.status==PBStatuses::BURN && code & 0b1000 == 0b1000 #sp.def boosting
    end
    if checkAImoves(PBStuff::SWITCHOUTMOVE,aimem)
      miniscore*=0.5 if sweep
      miniscore*=0.2 if !sweep
      miniscore*=1.5 if code == 0 #correction for evasion moves
    end
    if (!attacker.abilitynulled && attacker.ability == PBAbilities::SIMPLE)
      miniscore*=2
    end
    if @doublebattle
      miniscore*=0.5
      miniscore*=0.5 if !sweep  #drop is doubled
    end
    return miniscore
  end

  def hasgreatmoves(initialscores,scoreindex,skill)
    #slight variance in precision based on trainer skill
    threshold = 100
    threshold = 105 if skill>=PBTrainerAI.highSkill
    threshold = 110 if skill>=PBTrainerAI.bestSkill
    for i in 0...initialscores.length
      next if i==scoreindex
      if initialscores[i]>=threshold
        return true
      end
    end
    return false
  end

  def hasbadmoves(initialscores,scoreindex,threshold)
    for i in 0...initialscores.length
      next if i==scoreindex
      if initialscores[i]>threshold
        return false
      end
    end
    return false
  end

  def unsetupminiscore(attacker,opponent,skill,move,roles,type,physical,greatmoves=false)
    #general processing for stat-dropping moves
    #attack stat = type 1   defense stat = type 2   speed = 3   evasion = no
    miniscore = 100
    aimem = getAIMemory(skill,opponent.pokemonIndex)
    if type == 3  #speed stuff
      if (pbRoughStat(opponent,PBStats::SPEED,skill)*0.66)<attacker.pbSpeed
        if greatmoves
          miniscore*=1.5 if greatmoves
        else
          miniscore*=1.1
        end
      end
    else    #non-speed stuff
      count=-1
      party=pbParty(attacker.index)
      sweepvar=false
      for i in 0...party.length
        count+=1
        next if (count==attacker.pokemonIndex || party[i].nil?)
        temproles = pbGetMonRole(party[i],opponent,skill,count,party)
        if temproles.include?(PBMonRoles::SWEEPER)
          sweepvar=true
        end
      end
      if sweepvar
        miniscore*=1.1
      end
    end
    if type == 2    #defense stuff
      miniscore*=1.5 if checkAIhealing(aimem)
      miniscore*=1.5 if move.function == 0x4C
    else
      if roles.include?(PBMonRoles::PHYSICALWALL) || roles.include?(PBMonRoles::SPECIALWALL)
        miniscore*=1.3 if type == 1
        miniscore*=1.1 if type == 3
      end
    end
    livecount1=0
    for i in pbParty(attacker.index)
      next if i.nil?
      livecount1+=1 if i.hp!=0
    end
    livecount2=0
    for i in pbParty(opponent.index)
      next if i.nil?
      livecount2+=1 if i.hp!=0
    end
    if livecount2==1 || (!attacker.abilitynulled && attacker.ability == PBAbilities::SHADOWTAG) || opponent.effects[PBEffects::MeanLook]>0
      miniscore*=1.4
    end
    #status section
    if type == 2 || !physical
      miniscore*=1.2 if opponent.status==PBStatuses::POISON || opponent.status==PBStatuses::BURN
    elsif type == 1
      miniscore*=1.2 if opponent.status==PBStatuses::POISON
      miniscore*=0.5 if opponent.status==PBStatuses::BURN
    end
    #move checks
    if type == 1 && physical
      miniscore*=0.5 if attacker.pbHasMove?(PBMoves::FOULPLAY)
    elsif type == 3
      miniscore*=0.5 if attacker.pbHasMove?(PBMoves::GYROBALL)
      miniscore*=1.5 if attacker.pbHasMove?(PBMoves::ELECTROBALL)
      miniscore*=1.3 if checkAImoves([PBMoves::ELECTROBALL],aimem)
      miniscore*=0.5 if checkAImoves([PBMoves::GYROBALL],aimem)
      miniscore*=0.1 if  @trickroom!=0 || checkAImoves([PBMoves::TRICKROOM],aimem)
    end
    #final things
    if type == 3
      miniscore*=0.1 if opponent.itemWorks? && (opponent.item == PBItems::LAGGINGTAIL || opponent.item == PBItems::IRONBALL)
      miniscore*=0.2 if !opponent.abilitynulled && (opponent.ability == PBAbilities::COMPETITIVE || opponent.ability == PBAbilities::DEFIANT || opponent.ability == PBAbilities::CONTRARY)
    else
      miniscore*=0.1 if !opponent.abilitynulled && (opponent.ability == PBAbilities::UNAWARE  || opponent.ability == PBAbilities::COMPETITIVE || opponent.ability == PBAbilities::DEFIANT || opponent.ability == PBAbilities::CONTRARY)
    end
    if move.basedamage>0
      miniscore-=100
      if move.addlEffect.to_f != 100
        miniscore*=(move.addlEffect.to_f/100)
        if !attacker.abilitynulled && attacker.ability == PBAbilities::SERENEGRACE
          miniscore*=2
        end
      end
      miniscore+=100
    else
      if livecount1==1
        miniscore*=0.5
      end
      if attacker.status!=0
        miniscore*=0.7
      end
    end
    miniscore /= 100
    return miniscore
  end

  def statchangecounter(mon,initial,final,limiter=0)
    count = 0
    case limiter
      when 0 #all stats
        for i in initial..final
          count += mon.stages[i]
        end
      when 1 #increases only
        for i in initial..final
          count += mon.stages[i] if mon.stages[i]>0
        end
      when -1 #decreases only
        for i in initial..final
          count += mon.stages[i] if mon.stages[i]<0
        end
    end
    return count
  end

################################################################################
# AI Memory utility functions
################################################################################

  def getAIMemory(skill,index=0)
    if skill>=PBTrainerAI.bestSkill
      return @aiMoveMemory[2][index]
    elsif skill>=PBTrainerAI.highSkill
      return @aiMoveMemory[1]
    elsif skill>=PBTrainerAI.mediumSkill
      return @aiMoveMemory[0]
    else
      return []
    end
  end

  def checkAImoves(moveID,memory)
    #basic "does the other mon have x"
    return false if memory.length == 0
    for i in moveID
      for j in memory
        j = pbChangeMove(j,nil)#doesn't matter that i'm passing nil, won't get used
        return true if i == j.id #i should already be an ID here
      end
    end
    return false
  end

  def checkAIhealing(memory)
    #less basic "can the other mon heal"
    return false if memory.length == 0
    for j in memory
      return true if j.isHealingMove?
    end
    return false
  end

  def checkAIpriority(memory)
    #"does the other mon have priority"
    return false if memory.length == 0
    for j in memory
      return true if j.priority>0
    end
    return false
  end

  def checkAIaccuracy(memory)
    #"does the other mon have moves that don't miss"
    return false if memory.length == 0
    for j in memory
      j = pbChangeMove(j,nil)
      return true if j.accuracy==0
    end
    return false
  end

  def checkAIdamage(memory,attacker,opponent,skill)
    #returns how much damage the AI expects to take
    return -1 if memory.length == 0
    maxdam=0
    for j in memory
      tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)
      maxdam=tempdam if tempdam>maxdam
    end
    return maxdam
  end

  def checkAIbest(memory,modifier,type=[],usepower=true,attacker=nil,opponent=nil,skill=nil)
    return false if memory.length == 0
    #had to split this because switching ai uses power
    bestmove = 0
    if usepower
      biggestpower = 0
      for j in memory
        if j.basedamage>biggestpower
          biggestpower=j.basedamage
          bestmove=j
        end
      end
    else #maxdam
      maxdam=0
      for j in memory
        tempdam = pbRoughDamage(j,opponent,attacker,skill,j.basedamage)
        if tempdam>maxdam
          maxdam=tempdam
          bestmove=j
        end
      end
    end
    return false if bestmove==0
    #i don't want to make multiple functions for rare cases
    #we're doing it in one and you're gonna like it
    case modifier
      when 1 #type mod. checks types from a list.
        return true if type.include?(bestmove.type)
      when 2 #physical mod.
        return true if bestmove.pbIsPhysical?(bestmove.type)
      when 3 #special mod.
        return true if bestmove.pbIsSpecial?(bestmove.type)
      when 4 #contact mod.
        return true if bestmove.isContactMove?
      when 5 #sound mod.
        return true if bestmove.isSoundBased?
      when 6 #why.
        return true if (PBStuff::BULLETMOVE).include?(bestmove.id)
    end
    return false #you're still here? it's over! go home.
  end

################################################################################
# Choose a move to use.
################################################################################
  def pbBuildMoveScores(index) #Generates an array of movescores for decisions
    # Ally targetting stuff marked with ###
    attacker=@battlers[index]
    @scores=[0,0,0,0]
    @targets=nil
    @myChoices=[]
    totalscore=0
    target=-1
    skill=0
    wildbattle=!@opponent && opposes?(index)
    if wildbattle # If wild battle
      preference = attacker.personalID % 16
      preference = preference % 4
      for i in 0...4
        if pbCanChooseMove?(index,i,false)
          @scores[i]=100
          if preference == i # for personality
            @scores[i]+=100
          end
          @myChoices.push(i)
        end
      end
    else
      skill=pbGetOwner(attacker.index).skill || 0
      opponent=attacker.pbOppositeOpposing
      fastermon = (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
      if fastermon && opponent
        PBDebug.log(sprintf("AI Pokemon #{attacker.name} is faster than #{opponent.name}.")) if $INTERNAL
      elsif opponent
        PBDebug.log(sprintf("Player Pokemon #{opponent.name} is faster than #{attacker.name}.")) if $INTERNAL
      end
      #if @doublebattle && !opponent.isFainted? && !opponent.pbPartner.isFainted?
      if @doublebattle && ((!opponent.isFainted? && !opponent.pbPartner.isFainted?) || !attacker.pbPartner.isFainted?)
        # Choose a target and move.  Also care about partner.
        otheropp=opponent.pbPartner
        fastermon = (attacker.pbSpeed>pbRoughStat(opponent,PBStats::SPEED,skill)) ^ (@trickroom!=0)
        if fastermon && otheropp
          PBDebug.log(sprintf("AI Pokemon #{attacker.name} is faster than #{otheropp.name}.")) if $INTERNAL
        elsif otheropp
          PBDebug.log(sprintf("Player Pokemon #{otheropp.name} is faster than #{attacker.name}.")) if $INTERNAL
        end
        notopp=attacker.pbPartner ###
        scoresAndTargets=[]
        @targets=[-1,-1,-1,-1]
        maxscore1=0
        maxscore2=0
        totalscore1=0
        totalscore2=0
        baseDamageArray=[]
        baseDamageArray2=[]
        baseDamageArray3=[] ###
        for j in 0...4
          next if attacker.moves[j].id < 1
          # check attacker.moves[j].basedamage and if this is 0 instead check the status method
          dmgValue = pbRoughDamage(attacker.moves[j],attacker,opponent,skill,attacker.moves[j].basedamage)
          if attacker.moves[j].basedamage!=0
            if opponent.hp==0
              dmgPercent = 0
            else
              dmgPercent = (dmgValue*100)/(opponent.hp)
              dmgPercent = 110 if dmgPercent > 110
            end
          else
            dmgPercent = pbStatusDamage(attacker.moves[j])
          end
          baseDamageArray.push(dmgPercent)
          #Second opponent
          dmgValue2 = pbRoughDamage(attacker.moves[j],attacker,otheropp,skill,attacker.moves[j].basedamage)
          if attacker.moves[j].basedamage!=0
            if otheropp.hp==0
              dmgPercent2=0
            else
              dmgPercent2 = (dmgValue2*100)/(otheropp.hp)
              dmgPercent2 = 110 if dmgPercent2 > 110
            end
          else
            dmgPercent2 = pbStatusDamage(attacker.moves[j])
          end
          baseDamageArray2.push(dmgPercent2)
          #Partner ###
          dmgValue3 = pbRoughDamage(attacker.moves[j],attacker,notopp,skill,attacker.moves[j].basedamage)
          if attacker.moves[j].basedamage!=0
            if notopp.hp==0
              dmgPercent3=0
            else
              dmgPercent3 = (dmgValue3*100)/(notopp.hp)
              dmgPercent3 = 110 if dmgPercent3 > 110
            end
          else
            dmgPercent3 = pbStatusDamage(attacker.moves[j])
          end
          baseDamageArray3.push(dmgPercent3)
        end
        for i in 0...4
          if pbCanChooseMove?(index,i,false)
            score1=pbGetMoveScore(attacker.moves[i],attacker,opponent,skill,baseDamageArray[i],baseDamageArray,i)
            score2=pbGetMoveScore(attacker.moves[i],attacker,otheropp,skill,baseDamageArray2[i],baseDamageArray2,i)
            totalscore = score1+score2
            if (attacker.moves[i].target&0x08)!=0 # Targets all users
              score1=totalscore # Consider both scores as it will hit BOTH targets
              score2=totalscore
              if attacker.pbPartner.isFainted? || (!attacker.pbPartner.abilitynulled && attacker.pbPartner.ability == PBAbilities::TELEPATHY) # No partner
                  score1*=1.66
                  score2*=1.66
              else
                # If this move can also target the partner, get the partner's
                # score too
                v=pbRoughDamage(attacker.moves[i],attacker,attacker.pbPartner,skill,attacker.moves[i].basedamage)
                p=(v*100)/(attacker.pbPartner.hp)
                s=pbGetMoveScore(attacker.moves[i],attacker,attacker.pbPartner,skill,p)
                s=110 if s>110
                if !attacker.pbPartner.abilitynulled && (attacker.moves[i].type == PBTypes::FIRE && attacker.pbPartner.ability == PBAbilities::FLASHFIRE) ||
                  (attacker.moves[i].type == PBTypes::WATER && (attacker.pbPartner.ability == PBAbilities::WATERABSORB || attacker.pbPartner.ability == PBAbilities::STORMDRAIN || attacker.pbPartner.ability == PBAbilities::DRYSKIN)) ||
                  (attacker.moves[i].type == PBTypes::GRASS && attacker.pbPartner.ability == PBAbilities::SAPSIPPER) ||
                  (attacker.moves[i].type == PBTypes::ELECTRIC)&& (attacker.pbPartner.ability == PBAbilities::VOLTABSORB || attacker.pbPartner.ability == PBAbilities::LIGHTNINGROD || attacker.pbPartner.ability == PBAbilities::MOTORDRIVE)
                  score1*=2.00
                  score2*=2.00
                else
                  if (attacker.pbPartner.hp.to_f)/attacker.pbPartner.totalhp>0.10 || ((attacker.pbPartner.pbSpeed<attacker.pbSpeed) ^ (@trickroom!=0))
                    s = 100-s
                    s=0 if s<0
                    s/=100.0
                    s * 0.5 # multiplier to control how much to arbitrarily care about hitting partner; lower cares more
                    if (attacker.pbPartner.pbSpeed<attacker.pbSpeed) ^ (@trickroom!=0)
                      s * 0.5 # care more if we're faster and would knock it out before it attacks
                    end
                    score1*=s
                    score2*=s
                  end
                end
              end
              score1=score1.to_i
              score2=score2.to_i
              PBDebug.log(sprintf("%s: Final Score after Multi-Target Adjustment: %d",PBMoves.getName(attacker.moves[i].id),score1))
              PBDebug.log(sprintf(""))
            end
            if attacker.moves[i].target==PBTargets::AllOpposing # Consider both scores as it will hit BOTH targets
              totalscore = score1+score2
              score1=totalscore
              score2=totalscore
              PBDebug.log(sprintf("%s: Final Score after Multi-Target Adjustment: %d",PBMoves.getName(attacker.moves[i].id),score1))
              PBDebug.log(sprintf(""))
            end
            @myChoices.push(i)
            scoresAndTargets.push([i*2,i,score1,opponent.index])
            scoresAndTargets.push([i*2+1,i,score2,otheropp.index])
          else
            scoresAndTargets.push([i*2,i,-1,opponent.index])
            scoresAndTargets.push([i*2+1,i,-1,otheropp.index])
          end
        end
        for i in 0...4 ### This whole bit
          if pbCanChooseMove?(index,i,false)
            movecode = attacker.moves[i].function
            if movecode == 0xDF || movecode == 0x63 || movecode == 0x67 || #Heal Pulse, Simple Beam, Skill Swap,
              movecode == 0xA0 || movecode == 0xC1 || movecode == 0x142 || #Frost Breath, Beat Up, Topsy-Turvy,
              movecode == 0x162 || movecode == 0x164 || movecode == 0x167 || #Floral Healing, Instruct, Pollen Puff,
              movecode == 0x169 || movecode == 0x170 || movecode == 0x55 || #Purify, Spotlight, Psych Up,
              movecode == 0x40 || movecode == 0x41 || movecode == 0x66  #Swagger, Flatter, Entrainment
              partnerscore=pbGetMoveScore(attacker.moves[i],attacker,notopp,skill,baseDamageArray3[i],baseDamageArray3,i)
              PBDebug.log(sprintf("%s: Score for using on partner: %d",PBMoves.getName(attacker.moves[i].id),partnerscore))
              PBDebug.log(sprintf(""))
              scoresAndTargets.push([i*10,i,partnerscore,notopp.index])
            end
          end
        end
        scoresAndTargets.sort!{|a,b|
           if a[2]==b[2] # if scores are equal
             a[0]<=>b[0] # sort by index (for stable comparison)
           else
             b[2]<=>a[2]
           end
        }
        for i in 0...scoresAndTargets.length
          idx=scoresAndTargets[i][1]
          thisScore=scoresAndTargets[i][2]
          if thisScore>0 || thisScore==-1
            if scores[idx]==0 || ((scores[idx]==thisScore && pbAIRandom(10)<5) ||
               (scores[idx] < thisScore))
           #    (scores[idx]!=thisScore && pbAIRandom(10)<3))
              @scores[idx]=thisScore
              @targets[idx]=scoresAndTargets[i][3]
            end
          end
        end
      else
        # Choose a move. There is only 1 opposing Pokémon.
        if @doublebattle && opponent.isFainted?
          opponent=opponent.pbPartner
        end
        baseDamageArray=[]
        baseDamageArrayAdj=[]
        for j in 0...4
          next if attacker.moves[j].id < 1
          # check attacker.moves[j].basedamage and if this is 0 instead check the status method
          dmgValue = pbRoughDamage(attacker.moves[j],attacker,opponent,skill,attacker.moves[j].basedamage)
          if attacker.moves[j].basedamage!=0
            dmgPercent = (dmgValue*100)/(opponent.hp)
            dmgPercent = 110 if dmgPercent > 110
            if attacker.moves[j].function == 0x115 || attacker.moves[j].function == 0xC3 ||
             attacker.moves[j].function == 0xC4 || attacker.moves[j].function == 0xC5 ||
             attacker.moves[j].function == 0xC6 || attacker.moves[j].function == 0xC7 ||
             attacker.moves[j].function == 0xC8
               dmgPercentAdj = (dmgPercent * 0.5)
            else
               dmgPercentAdj = dmgPercent
            end
          else
            dmgPercent = pbStatusDamage(attacker.moves[j])
            dmgPercentAdj = dmgPercent
          end
          baseDamageArray.push(dmgPercent)
          baseDamageArrayAdj.push(dmgPercentAdj)
        end
        for i in 0...4
          if pbCanChooseMove?(index,i,false)
            @scores[i]=pbGetMoveScore(attacker.moves[i],attacker,opponent,skill,baseDamageArray[i],baseDamageArrayAdj,i)
            @myChoices.push(i)
          else
            @scores[i] = -1
          end
        end
      end
    end
  end

  def pbChooseMoves(index)
    maxscore=0
    totalscore=0
    attacker=@battlers[index]
    skill=pbGetOwner(attacker.index).skill rescue 0
    wildbattle=!@opponent && opposes?(index)
    for i in 0...4
      #next if scores[i] == -1
      @scores[i]=0 if @scores[i]<0
      maxscore=@scores[i] if @scores[i]>maxscore
      totalscore+=@scores[i]
    end
    # Minmax choices depending on AI
    if !wildbattle && skill>=PBTrainerAI.mediumSkill
      threshold=(skill>=PBTrainerAI.bestSkill) ? 1.5 : (skill>=PBTrainerAI.highSkill) ? 2 : 3
      newscore=(skill>=PBTrainerAI.bestSkill) ? 5 : (skill>=PBTrainerAI.highSkill) ? 10 : 15
      for i in 0...@scores.length
        if @scores[i]>newscore && @scores[i]*threshold<maxscore
          totalscore-=(@scores[i]-newscore)
          @scores[i]=newscore
        end
      end
    end
    if $INTERNAL
      x="[#{attacker.pbThis}: "
      j=0
      for i in 0...4
        if attacker.moves[i].id!=0
          x+=", " if j>0
          x+=PBMoves.getName(attacker.moves[i].id)+"="+@scores[i].to_s
          j+=1
        end
      end
      x+="]"
      PBDebug.log(x)
    end
    if !wildbattle #&& maxscore>100
      stdev=pbStdDev(@scores)
        preferredMoves=[]
        for i in 0...4
          if attacker.moves[i].id!=0 && (@scores[i] >= (maxscore* 0.95)) && pbCanChooseMove?(index,i,false)
            preferredMoves.push(i)
            preferredMoves.push(i) if @scores[i]==maxscore # Doubly prefer the best move
          end
        end
        if preferredMoves.length>0
          i=preferredMoves[pbAIRandom(preferredMoves.length)]
          PBDebug.log("[Prefer "+PBMoves.getName(attacker.moves[i].id)+"]") if $INTERNAL
          pbRegisterMove(index,i,false)
          target=@targets[i] if @targets
          if @doublebattle && target && target>=0
            pbRegisterTarget(index,target)
          end
          return
        end
      #end
    end
    PBDebug.log("If this battle is not wild, something has gone wrong in scoring moves (no preference chosen).") if $INTERNAL
    if !wildbattle && attacker.turncount
      badmoves=false
      if ((maxscore<=20 && attacker.turncount>2) ||
         (maxscore<=30 && attacker.turncount>5)) && pbAIRandom(10)<8
        badmoves=true
      end
      if totalscore<100 && attacker.turncount>1
        badmoves=true
        movecount=0
        for i in 0...4
          if attacker.moves[i].id!=0
            if @scores[i]>0 && attacker.moves[i].basedamage>0
              badmoves=false
            end
            movecount+=1
          end
        end
        badmoves=badmoves && pbAIRandom(10)!=0
      end
    end
    if maxscore<=0
      # If all scores are 0 or less, choose a move at random
      if @myChoices.length>0
        pbRegisterMove(index,@myChoices[pbAIRandom(@myChoices.length)],false)
      else
        pbAutoChooseMove(index)
      end
    else
      randnum=pbAIRandom(totalscore)
      cumtotal=0
      for i in 0...4
        if @scores[i]>0
          cumtotal+=@scores[i]
          if randnum<cumtotal
            pbRegisterMove(index,i,false)
            target=@targets[i] if @targets
            break
          end
        end
      end
    end
    if @doublebattle && target && target>=0
      pbRegisterTarget(index,target)
    end
  end

################################################################################
# Decide whether the opponent should Mega Evolve their Pokémon.
################################################################################
  def pbEnemyShouldMegaEvolve?(index)
    # Simple "always should if possible"
    return pbCanMegaEvolve?(index)
  end


################################################################################
# Decide whether the opponent should Ultra Burst their Pokémon.
################################################################################
  def pbEnemyShouldUltraBurst?(index)
    # Simple "always should if possible"
    return pbCanUltraBurst?(index)
  end

################################################################################
# Decide whether the opponent should use a Z-Move.
################################################################################
  def pbEnemyShouldZMove?(index)
    return pbCanZMove?(index) #Conditions based on effectiveness and type handled later
  end

################################################################################
# Decide whether the opponent should use an item on the Pokémon.
################################################################################
  def pbEnemyShouldUseItem?(index)
    item=pbEnemyItemToUse(index)
    if item>0 && @battlers[index].effects[PBEffects::Embargo]==0
      pbRegisterItem(index,item,nil)
      return true
    end
    return false
  end

  def pbEnemyItemAlreadyUsed?(index,item,items)
    if @choices[1][0]==3 && @choices[1][1]==item
      qty=0
      for i in items
        qty+=1 if i==item
      end
      return true if qty<=1
    end
    return false
  end

  def pbEnemyItemToUse(index)
    return 0 if !@opponent
    return 0 if !@internalbattle
    items=pbGetOwnerItems(index)
    return 0 if !items
    skill=pbGetOwner(index).skill || 0
    battler=@battlers[index]
    party = pbParty(index)
    opponent1 = battler.pbOppositeOpposing
    opponent2 = opponent1.pbPartner
    currentroles = pbGetMonRole(battler,opponent1,skill)
    return 0 if battler.isFainted?
    highscore = 0
    movecount = -1
    maxplaypri = -1
    partynumber = 0
    aimem = getAIMemory(skill,opponent1.pokemonIndex)
    for i in party
      next if i.nil?
      next if i.hp == 0
      partynumber+=1
    end
    itemnumber = 0
    for i in items
      next if pbEnemyItemAlreadyUsed?(index,i,items)
      itemnumber+=1
    end
    #highest score
    for i in battler.moves
      scorearray = 0
      scorearray = @scores[i] if @scores[i]
      if scorearray>100 && i.priority>maxplaypri
        maxplaypri = i.priority
      end
    end
    highscore = @scores.max
    highdamage = -1
    maxopppri = -1
    pridam = -1
    bestid = -1
    #expected damage
    #if battler.pbSpeed<pbRoughStat(opponent1,PBStats::SPEED,skill)
    if aimem.length > 0
      for i in aimem
        tempdam = pbRoughDamage(i,opponent1,battler,skill,i.basedamage)
        if tempdam>highdamage
          highdamage = tempdam
          bestid = i.id
        end
        if i.priority > maxopppri
          maxopppri = i.priority
          pridam = tempdam
        end
      end
    end
    highratio = -1
    #expected damage percentage
    if battler.hp!=0
      highratio = highdamage*(1.0/battler.hp)
    end
    scorearray = []
    arraycount = -1
    PBDebug.log(sprintf("Beginning AI Item use check.")) if $INTERNAL
    PBDebug.log(sprintf(" ")) if $INTERNAL
    for i in items
      arraycount+=1
      scorearray.push(0)
      itemscore=100
      ishpitem = false
      isstatusitem = false
      next if pbEnemyItemAlreadyUsed?(index,i,items)
      if (i== PBItems::POTION) ||
         (i== PBItems::ULTRAPOTION) ||
         (i== PBItems::SUPERPOTION) ||
         (i== PBItems::HYPERPOTION) ||
         (i== PBItems::MAXPOTION) ||
         (i== PBItems::FULLRESTORE) ||
         (i== PBItems::FRESHWATER) ||
         (i== PBItems::SODAPOP) ||
         (i== PBItems::LEMONADE) ||
         (i== PBItems::MOOMOOMILK) ||
         (i== PBItems::MEMEONADE) ||
         (i== PBItems::STRAWBIC) ||
         (i== PBItems::CHOCOLATEIC) ||
         (i== PBItems::BLUEMIC)
        ishpitem=true
      end
      if (i== PBItems::FULLRESTORE) ||
         (i== PBItems::FULLHEAL) ||
         (i== PBItems::RAGECANDYBAR) ||
         (i== PBItems::LAVACOOKIE) ||
         (i== PBItems::OLDGATEAU) ||
         (i== PBItems::CASTELIACONE) ||
         (i== PBItems::LUMIOSEGALETTE) ||
         (i== PBItems::BIGMALASADA)
        isstatusitem=true
      end
      if ishpitem
        PBDebug.log(sprintf("This is a HP-healing item.")) if $INTERNAL
        restoreamount=0
        if (i== PBItems::POTION)
          restoreamount=20
        elsif (i== PBItems::ULTRAPOTION)
          restoreamount=200
        elsif (i== PBItems::SUPERPOTION)
          restoreamount=60
        elsif (i== PBItems::HYPERPOTION)
          restoreamount=120
        elsif (i== PBItems::MAXPOTION) || (i== PBItems::FULLRESTORE)
          restoreamount=battler.totalhp
        elsif (i== PBItems::FRESHWATER)
          restoreamount=30
        elsif (i== PBItems::SODAPOP)
          restoreamount=50
        elsif (i== PBItems::LEMONADE)
          restoreamount=70
        elsif (i== PBItems::MOOMOOMILK)
          restoreamount=110
        elsif (i== PBItems::MEMEONADE)
          restoreamount=103
        elsif (i== PBItems::STRAWBIC)
          restoreamount=90
        elsif (i== PBItems::CHOCOLATEIC)
          restoreamount=70
        elsif (i== PBItems::BLUEMIC)
          restoreamount=200
        end
        resratio=restoreamount*(1.0/battler.totalhp)
        itemscore*= (2 - (2*(battler.hp*(1.0/battler.totalhp))))
        if highdamage>=battler.hp
          if highdamage > [battler.hp+restoreamount,battler.totalhp].min
            itemscore*=0
          else
            itemscore*=1.2
          end
          healmove = false
          for j in battler.moves
            if j.isHealingMove?
              healmove=true
            end
          end
          if healmove
            if battler.pbSpeed < opponent1.pbSpeed
              if highdamage>=battler.hp
                itemscore*=1.1
              else
                itemscore*=0.6
                if resratio<0.55
                  itemscore*=0.2
                end
              end
            end
          end
        else
          itemscore*=0.4
        end
        if highdamage > restoreamount
          itemscore*=0
        else
          if restoreamount-highdamage < 15
            itemscore*=0.5
          end
        end
        if battler.pbSpeed > opponent1.pbSpeed
          itemscore*=0.8
          if highscore >=110
            if maxopppri > maxplaypri
              itemscore*=1.3
              if pridam>battler.hp
                if pridam>(battler.hp/2.0)
                  itemscore*=0
                else
                  itemscore*=2
                end
              end
            elsif !(!opponent1.abilitynulled && opponent1.ability == PBAbilities::STURDY)
              itemscore*=0
            end
          end
          if currentroles.include?(PBMonRoles::SWEEPER)
            itemscore*=1.1
          end
        else
          if highdamage*2 > [battler.hp+restoreamount,battler.totalhp].min
            itemscore*=0
          else
            itemscore*=1.5
            if highscore >=110
              itemscore*=1.5
            end
          end
        end
        if battler.hp == battler.totalhp
          itemscore*=0
        elsif battler.hp >= (battler.totalhp*0.8)
          itemscore*=0.2
        elsif battler.hp >= (battler.totalhp*0.6)
          itemscore*=0.3
        elsif battler.hp >= (battler.totalhp*0.5)
          itemscore*=0.5
        end
        minipot = (partynumber-1)
        minimini = -1
        for j in items
          next if pbEnemyItemAlreadyUsed?(index,j,items)
          next if !((j== PBItems::POTION) || (j== PBItems::ULTRAPOTION) || 
          (j== PBItems::SUPERPOTION) || (j== PBItems::HYPERPOTION) || 
          (j== PBItems::MAXPOTION) || (j== PBItems::FULLRESTORE) || 
          (j== PBItems::FRESHWATER) || (j== PBItems::SODAPOP) || 
          (j== PBItems::LEMONADE) || (j== PBItems::MOOMOOMILK) || 
          (j== PBItems::MEMEONADE) || (j== PBItems::STRAWBIC) || 
          (j== PBItems::CHOCOLATEIC) || (j== PBItems::BLUEMIC))
          minimini+=1
        end
        if minipot>minimini
          itemscore*=(0.9**(minipot-minimini))
          minipot=minimini
        elsif minimini>minipot
          itemscore*=(1.1**(minimini-minipot))
          minimini=minipot
        end
        if currentroles.include?(PBMonRoles::LEAD) || currentroles.include?(PBMonRoles::SCREENER)
          itemscore*=0.6
        end
        if currentroles.include?(PBMonRoles::TANK)
          itemscore*=1.1
        end
        if currentroles.include?(PBMonRoles::SECOND)
          itemscore*=1.1
        end
        if battler.hasWorkingItem(:LEFTOVERS) || (battler.hasWorkingItem(:BLACKSLUDGE) && battler.pbHasType?(:POISON))
          itemscore*=0.9
        end
        if battler.status!=0 && !(i== PBItems::FULLRESTORE)
          itemscore*=0.7
          if battler.effects[PBEffects::Toxic]>0 && partynumber>1
            itemscore*=0.2
          end
        end
        if PBTypes.getCombinedEffectiveness(opponent1.type1,battler.type1,battler.type2)>4
          itemscore*=0.7
        elsif PBTypes.getCombinedEffectiveness(opponent1.type1,battler.type1,battler.type2)<4
          itemscore*=1.1
          if PBTypes.getCombinedEffectiveness(opponent1.type1,battler.type1,battler.type2)==0
            itemscore*=1.2
          end
        end
        if PBTypes.getCombinedEffectiveness(opponent1.type2,battler.type1,battler.type2)>4
          itemscore*=0.6
        elsif PBTypes.getCombinedEffectiveness(opponent1.type1,battler.type1,battler.type2)<4
          itemscore*=1.1
          if PBTypes.getCombinedEffectiveness(opponent1.type1,battler.type1,battler.type2)==0
            itemscore*=1.2
          end
        end
        if (!battler.abilitynulled && battler.ability == PBAbilities::REGENERATOR) && partynumber>1
          itemscore*=0.7
        end
      end
      if isstatusitem
        PBDebug.log(sprintf("This is a status-curing item.")) if $INTERNAL
        if !(i== PBItems::FULLRESTORE)
          if battler.status==0
            itemscore*=0
          else
            if highdamage>battler.hp
              if (bestid==106 && battler.status==PBStatuses::SLEEP) || (bestid==298 && battler.status==PBStatuses::PARALYSIS) || bestid==179
                if highdamage*0.5>battler.hp
                  itemscore*=0
                else
                  itemscore*=1.4
                end
              else
                itemscore*=0
              end
            end
          end
          if battler.status==PBStatuses::SLEEP
            if battler.pbHasMove?((PBMoves::SLEEPTALK)) ||
              battler.pbHasMove?((PBMoves::SNORE)) ||
              battler.pbHasMove?((PBMoves::REST)) ||
              (!battler.abilitynulled && battler.ability == PBAbilities::COMATOSE)
              itemscore*=0.6
            end
            if checkAImoves([PBMoves::DREAMEATER,PBMoves::NIGHTMARE],aimem) || (!opponent1.abilitynulled && opponent1.ability == PBAbilities::BADDREAMS)
              itemscore*=1.3
            end
            if highdamage*(1.0/battler.hp)>0.2
              itemscore*=1.3
            else
              itemscore*=0.7
            end
          end
          if battler.status==PBStatuses::PARALYSIS
            if (!battler.abilitynulled && battler.ability == PBAbilities::QUICKFEET) || (!battler.abilitynulled && battler.ability == PBAbilities::GUTS)
              itemscore*=0.5
            end
            if battler.pbSpeed>opponent1.pbSpeed && (battler.pbSpeed*0.5)<opponent1.pbSpeed
              itemscore*=1.3
            end
            itemscore*=1.1
          end
          if battler.status==PBStatuses::BURN
            itemscore*=1.1
            if battler.attack>battler.spatk
              itemscore*=1.2
            else
              itemscore*=0.8
            end
            if !battler.abilitynulled 
              itemscore*=0.6 if battler.ability == PBAbilities::GUTS
              itemscore*=0.7 if battler.ability == PBAbilities::MAGICGUARD
              itemscore*=0.8 if battler.ability == PBAbilities::FLAREBOOST
            end
          end
          if battler.status==PBStatuses::POISON
            itemscore*=1.1
            if !battler.abilitynulled
              itemscore*=0.5 if battler.ability == PBAbilities::GUTS
              itemscore*=0.5 if battler.ability == PBAbilities::MAGICGUARD
              itemscore*=0.5 if battler.ability == PBAbilities::TOXICBOOST
              itemscore*=0.4 if battler.ability == PBAbilities::POISONHEAL
            end
            if battler.effects[PBEffects::Toxic]>0
              itemscore*=1.1
              if battler.effects[PBEffects::Toxic]>3
                itemscore*=1.3
              end
            end
          end
          if battler.status==PBStatuses::FROZEN
            itemscore*=1.3
            thawmove=false
            for j in battler.moves
              if j.canThawUser?
                thawmove=true
              end
            end
            if thawmove
              itemscore*=0.5
            end
            if highdamage*(1.0/battler.hp)>0.15
              itemscore*=1.1
            else
              itemscore*=0.9
            end
          end
        end
        if battler.pbHasMove?((PBMoves::REFRESH)) ||
          battler.pbHasMove?((PBMoves::REST)) ||
          battler.pbHasMove?((PBMoves::PURIFY))
          itemscore*=0.5
        end
        if (!battler.abilitynulled && battler.ability == PBAbilities::NATURALCURE) && partynumber>1
          itemscore*=0.2
        end
        if (!battler.abilitynulled && battler.ability == PBAbilities::SHEDSKIN)
          itemscore*=0.3
        end
      end
      if partynumber==1 || currentroles.include?(PBMonRoles::ACE)
        itemscore*=1.2
      else
        itemscore*=0.8
        if battler.itemUsed2
          itemscore*=0.6
        end
      end
      if battler.effects[PBEffects::Confusion]>0
        itemscore*=0.9
      end
      if battler.effects[PBEffects::Attract]>=0
        itemscore*=0.6
      end
      if battler.effects[PBEffects::Substitute]>0
        itemscore*=1.1
      end
      if battler.effects[PBEffects::LeechSeed]>=0
        itemscore*=0.5
      end
      if battler.effects[PBEffects::Curse]
        itemscore*=0.5
      end
      if battler.effects[PBEffects::PerishSong]>0
        itemscore*=0.2
      end
      minipot=0
      for s in [PBStats::ATTACK,PBStats::DEFENSE,PBStats::SPEED,
                PBStats::SPATK,PBStats::SPDEF,PBStats::ACCURACY,PBStats::EVASION]
        minipot+=battler.stages[s]
      end
      if currentroles.include?(PBMonRoles::PHYSICALWALL) || currentroles.include?(PBMonRoles::SPECIALWALL)
        for s in [PBStats::DEFENSE,PBStats::SPDEF]
          minipot+=battler.stages[s]
        end
      end
      if currentroles.include?(PBMonRoles::SWEEPER)
        for s in [PBStats::SPEED]
          minipot+=battler.stages[s]
        end
        if battler.attack>battler.spatk
          for s in [PBStats::ATTACK]
            minipot+=battler.stages[s]
          end
        else
          for s in [PBStats::SPATK]
            minipot+=battler.stages[s]
          end
        end
      end
      minipot*=5
      minipot+=100
      minipot*=0.01
      itemscore*=minipot
      if opponent1.effects[PBEffects::TwoTurnAttack]>0 || opponent1.effects[PBEffects::HyperBeam]>0
        itemscore*=1.2
      end
      if highscore>70
        itemscore*=1.1
      else
        itemscore*=0.9
      end
      fielddisrupt = getFieldDisruptScore(battler,opponent1,skill)
      if fielddisrupt <= 0
        fielddisrupt=0.6
      end
      itemscore*= (1.0/fielddisrupt)
      if @trickroom > 0
        itemscore*=0.9
      end
      if battler.pbOwnSide.effects[PBEffects::Tailwind]>0
        itemscore*=0.6
      end
      if battler.pbOwnSide.effects[PBEffects::Reflect]>0
        itemscore*=0.9
      end
      if battler.pbOwnSide.effects[PBEffects::LightScreen]>0
        itemscore*=0.9
      end
      if battler.pbOwnSide.effects[PBEffects::AuroraVeil]>0
        itemscore*=0.8
      end
      if @doublebattle
        itemscore*=0.8
      end
      itemscore-=100
      PBDebug.log(sprintf("Score for %s: %d",PBItems.getName(i),itemscore)) if $INTERNAL
      scorearray[arraycount] = itemscore
    end
    bestitem=-1
    bestscore=-10000
    counter=-1
    for k in scorearray
      counter+=1
      if k>bestscore
        bestscore = k
        bestitem = items[counter]
      end
    end
    PBDebug.log(sprintf("Highest item score: %d",bestscore)) if $INTERNAL
    PBDebug.log(sprintf("Highest move score: %d",highscore)) if $INTERNAL
    if highscore<bestscore
      PBDebug.log(sprintf("Using %s",PBItems.getName(bestitem))) if $INTERNAL
      return bestitem
    else
      PBDebug.log(sprintf("Not using an item.")) if $INTERNAL
      PBDebug.log(sprintf(" ")) if $INTERNAL
      return 0
    end
  end


################################################################################
# Decide whether the opponent should switch Pokémon, and what to switch to. NEW
################################################################################

  #if this function isn't here things break and i hate it.
  def pbDefaultChooseNewEnemy(index,party)
    return pbSwitchTo(@battlers[index],party,pbGetOwner(index).skill)
  end

  def pbShouldSwitch?(index)
    return false if !@opponent
    switchscore = 0
    noswitchscore = 0
    monarray = []
    currentmon = @battlers[index]
    opponent1 = currentmon.pbOppositeOpposing
    opponent2 = opponent1.pbPartner
    party = pbParty(index)
    partyroles=[]
    skill=pbGetOwner(index).skill || 0
    count = 0
    for i in party
      next if i.nil?
      next if i.hp == 0
      count+=1
    end
    return false if count==1
    if $game_switches[1000] && count==2
      return false
    end
    count = 0
    for i in 0..(party.length-1)
      next if !pbCanSwitchLax?(index,i,false)
      count+=1
    end
    return false if count==0
    count = -1
    for i in party
      count+=1
      next if i.nil?
      next if count == currentmon.pokemonIndex
      dummyarr1 = pbGetMonRole(i,opponent1,skill,count,party)
      (partyroles << dummyarr1).flatten!
      dummyarr2 = pbGetMonRole(i,opponent2,skill,count,party)
      (partyroles << dummyarr2).flatten!
    end
    partyroles.uniq!
    currentroles = pbGetMonRole(currentmon,opponent1,skill)
    aimem = getAIMemory(skill,opponent1.pokemonIndex)
    aimem2 = getAIMemory(skill,opponent2.pokemonIndex)
    # Statuses
    PBDebug.log(sprintf("Initial switchscore building: Statuses (%d)",switchscore)) if $INTERNAL
    if currentmon.effects[PBEffects::Curse]
      switchscore+=80
    end
    if currentmon.effects[PBEffects::LeechSeed]>=0
      switchscore+=60
    end
    if currentmon.effects[PBEffects::Attract]>=0
      switchscore+=60
    end
    if currentmon.effects[PBEffects::Confusion]>0
      switchscore+=80
    end
    if currentmon.effects[PBEffects::PerishSong]==2
      switchscore+=40
    elsif currentmon.effects[PBEffects::PerishSong]==1
      switchscore+=200
    end
    if currentmon.effects[PBEffects::Toxic]>0
      switchscore+= (currentmon.effects[PBEffects::Toxic]*15)
    end
    if (!currentmon.abilitynulled && currentmon.ability == PBAbilities::NATURALCURE) && currentmon.status!=0
      switchscore+=50
    end
    if partyroles.include?(PBMonRoles::CLERIC) && currentmon.status!=0
      switchscore+=60
    end
    if currentmon.status==PBStatuses::SLEEP
      switchscore+=170 if checkAImoves([PBMoves::DREAMEATER,PBMoves::NIGHTMARE],aimem)
    end
    if currentmon.effects[PBEffects::Yawn]>0 && currentmon.status!=PBStatuses::SLEEP
      switchscore+=95
    end
    # Stat Stages
    PBDebug.log(sprintf("Initial switchscore building: Stat Stages (%d)",switchscore)) if $INTERNAL
    specialmove = false
    physmove = false
    for i in currentmon.moves
      specialmove = true if i.pbIsSpecial?(i.type)
      physmove = true if i.pbIsPhysical?(i.type)
    end
    if currentroles.include?(PBMonRoles::SWEEPER)
      switchscore+= (-30)*currentmon.stages[PBStats::ATTACK] if currentmon.stages[PBStats::ATTACK]<0 && physmove
      switchscore+= (-30)*currentmon.stages[PBStats::SPATK] if currentmon.stages[PBStats::SPATK]<0 && specialmove
      switchscore+= (-30)*currentmon.stages[PBStats::SPEED] if currentmon.stages[PBStats::SPEED]<0
      switchscore+= (-30)*currentmon.stages[PBStats::ACCURACY] if currentmon.stages[PBStats::ACCURACY]<0
    else
      switchscore+= (-15)*currentmon.stages[PBStats::ATTACK] if currentmon.stages[PBStats::ATTACK]<0 && physmove
      switchscore+= (-15)*currentmon.stages[PBStats::SPATK] if currentmon.stages[PBStats::SPATK]<0 && specialmove
      switchscore+= (-15)*currentmon.stages[PBStats::SPEED] if currentmon.stages[PBStats::SPEED]<0
      switchscore+= (-15)*currentmon.stages[PBStats::ACCURACY] if currentmon.stages[PBStats::ACCURACY]<0
    end
    if currentroles.include?(PBMonRoles::PHYSICALWALL)
      switchscore+= (-30)*currentmon.stages[PBStats::DEFENSE] if currentmon.stages[PBStats::DEFENSE]<0
    else
      switchscore+= (-15)*currentmon.stages[PBStats::DEFENSE] if currentmon.stages[PBStats::DEFENSE]<0
    end
    if currentroles.include?(PBMonRoles::SPECIALWALL)
      switchscore+= (-30)*currentmon.stages[PBStats::SPDEF] if currentmon.stages[PBStats::SPDEF]<0
    else
      switchscore+= (-15)*currentmon.stages[PBStats::SPDEF] if currentmon.stages[PBStats::SPDEF]<0
    end
    # Healing
    PBDebug.log(sprintf("Initial switchscore building: Healing")) if $INTERNAL
    if (currentmon.hp.to_f)/currentmon.totalhp<(2/3) && (!currentmon.abilitynulled && currentmon.ability == PBAbilities::REGENERATOR)
      switchscore+=30
    end
    if currentmon.effects[PBEffects::Wish]>0
      lowhp = false
      for i in party
        next if i.nil?
        if 0.3<((i.hp.to_f)/i.totalhp) && ((i.hp.to_f)/i.totalhp)<0.6
          lowhp = true
        end
      end
      switchscore+=40 if lowhp
    end
    # fsteak
    PBDebug.log(sprintf("Initial switchscore building: fsteak (%d)",switchscore)) if $INTERNAL
    finalmod = 0
    tricktreat = false
    forestcurse = false
    notnorm = false
    for i in currentmon.moves
      if i.id==(PBMoves::TRICKORTREAT)
        tricktreat = true
      elsif i.id==(PBMoves::FORESTSCURSE)
        forestcurse = true
      elsif i.type != (PBTypes::NORMAL)
        notnorm = true
      end
      mod1 = pbTypeModNoMessages(i.type,currentmon,opponent1,i,skill)
      mod2 = pbTypeModNoMessages(i.type,currentmon,opponent2,i,skill)
      mod1 = 4 if opponent1.hp==0
      mod2 = 4 if opponent2.hp==0
      if (!opponent1.abilitynulled && opponent1.ability == PBAbilities::WONDERGUARD) && mod1<=4
        mod1=0
      end
      if (!opponent2.abilitynulled && opponent2.ability == PBAbilities::WONDERGUARD) && mod2<=4
        mod2=0
      end
      finalmod += mod1*mod2
    end
    if finalmod==0
      if (tricktreat && notnorm) || forestcurse
        finalmod=1
      end
    end
    switchscore+=140 if finalmod==0
    totalpp=0
    for i in currentmon.moves
      totalpp+= i.pp
    end
    switchscore+=200 if totalpp==0
    if currentmon.effects[PBEffects::Torment]== true
      switchscore+=30
    end
    if currentmon.effects[PBEffects::Encore]>0
      encoreIndex=currentmon.effects[PBEffects::EncoreIndex]
      if opponent1.hp>0
        dmgValue = pbRoughDamage(currentmon.moves[encoreIndex],currentmon,opponent1,skill,currentmon.moves[encoreIndex].basedamage)
        if currentmon.moves[encoreIndex].basedamage!=0
          dmgPercent = (dmgValue*100)/(opponent1.hp)
          dmgPercent = 110 if dmgPercent > 110
        else
          dmgPercent = pbStatusDamage(currentmon.moves[encoreIndex])
        end
        encoreScore=pbGetMoveScore(currentmon.moves[encoreIndex],currentmon,opponent1,skill,dmgPercent)
      else
        dmgValue = pbRoughDamage(currentmon.moves[encoreIndex],currentmon,opponent2,skill,currentmon.moves[encoreIndex].basedamage)
        if currentmon.moves[encoreIndex].basedamage!=0
          dmgPercent = (dmgValue*100)/(opponent2.hp)
          dmgPercent = 110 if dmgPercent > 110
        else
          dmgPercent = pbStatusDamage(currentmon.moves[encoreIndex])
        end
        encoreScore=pbGetMoveScore(currentmon.moves[encoreIndex],currentmon,opponent2,skill,dmgPercent)
      end
      if encoreScore <= 30
        switchscore+=200
      end
      if currentmon.effects[PBEffects::Torment]== true
        switchscore+=110
      end
    end
    if currentmon.effects[PBEffects::ChoiceBand]>=0 && currentmon.itemWorks? && (currentmon.item == PBItems::CHOICEBAND ||
        currentmon.item == PBItems::CHOICESPECS || currentmon.item == PBItems::CHOICESCARF)
      choiced = false
      for i in 0...4
        if currentmon.moves[i].id==currentmon.effects[PBEffects::ChoiceBand]
          choiced=true
          choiceID = i
          break
        end
      end
      if choiced
        if opponent1.hp>0
          dmgValue = pbRoughDamage(currentmon.moves[choiceID],currentmon,opponent1,skill,currentmon.moves[choiceID].basedamage)
          if currentmon.moves[choiceID].basedamage!=0
            dmgPercent = (dmgValue*100)/(opponent1.hp)
            dmgPercent = 110 if dmgPercent > 110
          else
            dmgPercent = pbStatusDamage(currentmon.moves[choiceID])
          end
          choiceScore=pbGetMoveScore(currentmon.moves[choiceID],currentmon,opponent1,skill,dmgPercent)
        else
          dmgValue = pbRoughDamage(currentmon.moves[choiceID],currentmon,opponent2,skill,currentmon.moves[choiceID].basedamage)
          if currentmon.moves[choiceID].basedamage!=0
            dmgPercent = (dmgValue*100)/(opponent2.hp)
            dmgPercent = 110 if dmgPercent > 110
          else
            dmgPercent = pbStatusDamage(currentmon.moves[choiceID])
          end
          choiceScore=pbGetMoveScore(currentmon.moves[choiceID],currentmon,opponent2,skill,dmgPercent)
        end
        if choiceScore <= 50
          switchscore+=50
          if choiceScore <= 30
            switchscore+=130
            if choiceScore <= 5
              switchscore+=150
            end
          end
        end
        if currentmon.effects[PBEffects::Torment]== true
          switchscore+=150
        end
      end
    end
    if skill<PBTrainerAI.highSkill
      switchscore/=2.0
    end
    # Typing? How have we not had a typing section this entire time?
    PBDebug.log(sprintf("Initial switchscore building: Typing (%d)",switchscore)) if $INTERNAL
    tempswitchscore = 0
    effcheck = PBTypes.getCombinedEffectiveness(opponent1.type1,currentmon.type1,currentmon.type2)
    if effcheck > 4
      tempswitchscore+=20
    elsif effcheck < 4
      tempswitchscore-=20
    end
    effcheck2 = PBTypes.getCombinedEffectiveness(opponent1.type2,currentmon.type1,currentmon.type2)
    if effcheck2 > 4
      tempswitchscore+=20
      elsif effcheck2 < 4
        tempswitchscore-=20
      end
    if opponent2.totalhp !=0
      tempswitchscore *= 0.5
      effcheck = PBTypes.getCombinedEffectiveness(opponent2.type1,currentmon.type1,currentmon.type2)
      if effcheck > 4
        tempswitchscore+=10
      elsif effcheck < 4
        tempswitchscore-=10
      end
      effcheck2 = PBTypes.getCombinedEffectiveness(opponent2.type2,currentmon.type1,currentmon.type2)
      if effcheck2 > 4
        tempswitchscore+=10
      elsif effcheck2 < 4
        tempswitchscore-=10
      end
    end
    switchscore += tempswitchscore
    # Specific Switches
    PBDebug.log(sprintf("Initial switchscore building: Specific Switches (%d)",switchscore)) if $INTERNAL
    if opponent1.effects[PBEffects::TwoTurnAttack]>0
      twoturntype = $pkmn_move[opponent1.effects[PBEffects::TwoTurnAttack]][2]
      breakvar = false
      savedmod = -1
      indexsave = -1
      count = -1
      for i in party
        count+=1
        next if i.nil?
        next if count == currentmon.pokemonIndex
        totalmod=currentmon.moves[0].pbTypeModifierNonBattler(twoturntype,opponent1,i)
        if totalmod<4
          switchscore+=80 unless breakvar
          breakvar = true
          if savedmod<0
            indexsave = count
            savedmod = totalmod
          else
            if savedmod>totalmod
              indexsave = count
              savedmod = totalmod
            end
          end
        end
      end
      monarray.push(indexsave) if indexsave > -1
    end
    if pbRoughStat(currentmon,PBStats::SPEED,skill) < pbRoughStat(opponent1,PBStats::SPEED,skill)
      if aimem.length!=0
        movedamages = []
        for i in aimem
          movedamages.push(pbRoughDamage(i,opponent1,currentmon,skill,i.basedamage))
        end
        if movedamages.length > 0
          bestmoveindex = movedamages.index(movedamages.max)
          bestmove = aimem[bestmoveindex]
          if (currentmon.hp) < movedamages[bestmoveindex]
            count = -1
            breakvar = false
            immunevar = false
            savedmod = -1
            indexsave = -1
            for i in party
              count+=1
              next if i.nil?
              next if count == currentmon.pokemonIndex
              totalmod = bestmove.pbTypeModifierNonBattler(bestmove.type,opponent1,i)
              if totalmod<4
                switchscore+=80 unless breakvar
                breakvar = true
                if totalmod == 0
                  switchscore+=20 unless immunevar
                  immunevar = true
                end
                if savedmod<0
                  indexsave = count
                  savedmod = totalmod
                else
                  if savedmod>totalmod
                    indexsave = count
                    savedmod = totalmod
                  end
                end
              end
            end
            if immunevar
              monarray.push(indexsave) if indexsave > -1
            else
              if indexsave > -1
                if party[indexsave].speed > pbRoughStat(opponent1,PBStats::SPEED,skill)
                  monarray.push(indexsave)
                end
              end
            end
          end
        end
      end
    end
    if pbRoughStat(currentmon,PBStats::SPEED,skill) < pbRoughStat(opponent2,PBStats::SPEED,skill)
      if aimem2.length!=0
        movedamages = []
        for i in aimem2
          movedamages.push(pbRoughDamage(i,opponent2,currentmon,skill,i.basedamage))
        end
        if movedamages.length > 0
          bestmoveindex = movedamages.index(movedamages.max)
          bestmove = aimem2[bestmoveindex]
          if (currentmon.hp) < movedamages[bestmoveindex]
            count = -1
            breakvar = false
            immunevar = false
            savedmod = -1
            indexsave = -1
            for i in party
              count+=1
              next if i.nil?
              next if count == currentmon.pokemonIndex
              totalmod = bestmove.pbTypeModifierNonBattler(bestmove.type,opponent2,i)
              if totalmod<4
                switchscore+=80 unless breakvar
                breakvar = true
                if totalmod == 0
                  switchscore+=20 unless immunevar
                  immunevar = true
                end
                if savedmod<0
                  indexsave = count
                  savedmod = totalmod
                else
                  if savedmod>totalmod
                    indexsave = count
                    savedmod = totalmod
                  end
                end
              end
            end
            if immunevar
              monarray.push(indexsave) if indexsave > -1
            else
              if indexsave > -1
                if party[indexsave].speed > pbRoughStat(opponent2,PBStats::SPEED,skill)
                  monarray.push(indexsave)
                end
              end
            end
          end
        end
      end
    end
    if skill>=PBTrainerAI.highSkill
      if aimem.length!=0
        #Fakeout Check
        if checkAImoves([PBMoves::FAKEOUT],aimem) && opponent1.turncount == 1
          count = -1
          for i in party
            count+=1
            next if i.nil?
            next if count == currentmon.pokemonIndex
            if (i.ability == PBAbilities::STEADFAST)
              monarray.push(count)
              switchscore+=90
              break
            end
          end
        end
        #Meech check
        if (opponent1.ability == PBAbilities::SKILLLINK) && skill>=PBTrainerAI.bestSkill #elite trainers only
          probablycinccino = false
          for i in aimem
            if i.function==0xC0 && i.isContactMove?
              probablycinccino = true
            end
          end
          if probablycinccino
            count = -1
            maxpain = 0
            storedmon = -1
            for i in party
              count+=1
              next if i.nil?
              paincount = 0
              next if count == currentmon.pokemonIndex
              if (i.ability == PBAbilities::ROUGHSKIN) || (i.ability == PBAbilities::IRONBARBS)
                paincount+=1
              end
              if (i.item == PBItems::ROCKYHELMET)
                paincount+=1
              end
              if paincount>0 && paincount>maxpain
                maxpain=paincount
                storedmon = count
                switchscore+=70
              end
            end
            if storedmon>-1
              monarray.push(storedmon)
            end
          end
        end
      end
      if aimem.length!=0
        #Fakeout Check
        if checkAImoves([PBMoves::FAKEOUT],aimem2) && opponent2.turncount == 1
          count = -1
          for i in party
            count+=1
            next if i.nil?
            next if count == currentmon.pokemonIndex
            if (i.ability == PBAbilities::STEADFAST)
              monarray.push(count)
              switchscore+=90
              break
            end
          end
        end
        #Meech check
        if (opponent2.ability == PBAbilities::SKILLLINK) && skill>=PBTrainerAI.bestSkill
          probablycinccino = false
          for i in aimem2
            if i.function==0xC0 && i.isContactMove?
              probablycinccino = true
            end
          end
          if probablycinccino
            count = -1
            maxpain = 0
            storedmon = -1
            for i in party
              count+=1
              next if i.nil?
              paincount = 0
              next if count == currentmon.pokemonIndex
              if (i.ability == PBAbilities::ROUGHSKIN) || (i.ability == PBAbilities::IRONBARBS)
                paincount+=1
              end
              if (i.item == PBItems::ROCKYHELMET)
                paincount+=1
              end
              if paincount>0 && paincount>maxpain
                maxpain=paincount
                storedmon = count
                switchscore+=70
              end
            end
            if storedmon>-1
              monarray.push(storedmon)
            end
          end
        end
      end
    end
    count = -1
    storedmon = -1
    storedhp = -1
    for i in party
      count+=1
      next if i.nil?
      next if i.totalhp==0
      next if count == currentmon.pokemonIndex
      next if !pbCanSwitchLax?(currentmon.index,count,false)
      if storedhp < 0
        storedhp = i.hp/(i.totalhp.to_f)
        storedmon = i #count
        storedcount = count
      else
        if storedhp > i.hp/(i.totalhp.to_f)
          storedhp = i.hp/(i.totalhp.to_f)
          storedmon = i #count
          storedcount = count
        end
      end
    end
    if storedhp < 0.20 && storedhp > 0
      if ((storedmon.speed < pbRoughStat(opponent1,PBStats::SPEED,skill)) && (
        storedmon.speed < pbRoughStat(opponent2,PBStats::SPEED,skill))) ||
        currentmon.pbOwnSide.effects[PBEffects::Spikes]>0 ||
        currentmon.pbOwnSide.effects[PBEffects::StealthRock]
        speedcheck = false
        for i in party
          next if i.nil?
          next if i==storedmon
          if i.speed > pbRoughStat(opponent1,PBStats::SPEED,skill)
            speedcheck = true
          end
        end
        if speedcheck
          monarray.push(storedcount)
          switchscore+=20
        end
      end
    end
    maxlevel = -1
    for i in party
      next if i.nil?
      if maxlevel < 0
        maxlevel = i.level
      else
        if maxlevel < i.level
          maxlevel = i.level
        end
      end
    end
    if maxlevel>(opponent1.level+10)
      switchscore-=100
      if maxlevel>(opponent1.level+20)
        switchscore-=1000
      end
    end
    PBDebug.log(sprintf("%s: initial switchscore: %d",PBSpecies.getName(@battlers[index].species),switchscore)) if $INTERNAL
    PBDebug.log(sprintf(" ")) if $INTERNAL
    # Stat Stages
    PBDebug.log(sprintf("Initial noswitchscore building: Stat Stages (%d)",noswitchscore)) if $INTERNAL
    specialmove = false
    physmove = false
    for i in currentmon.moves
      specialmove = true if i.pbIsSpecial?(i.type)
      physmove = true if i.pbIsPhysical?(i.type)
    end
    if currentroles.include?(PBMonRoles::SWEEPER)
      noswitchscore+= (30)*currentmon.stages[PBStats::ATTACK] if currentmon.stages[PBStats::ATTACK]>0 && physmove
      noswitchscore+= (30)*currentmon.stages[PBStats::SPATK] if currentmon.stages[PBStats::SPATK]>0 && specialmove
      noswitchscore+= (30)*currentmon.stages[PBStats::SPEED] if currentmon.stages[PBStats::SPEED]>0 unless (currentroles.include?(PBMonRoles::PHYSICALWALL) || currentroles.include?(PBMonRoles::SPECIALWALL) || currentroles.include?(PBMonRoles::TANK))
    else
      noswitchscore+= (15)*currentmon.stages[PBStats::ATTACK] if currentmon.stages[PBStats::ATTACK]>0 && physmove
      noswitchscore+= (15)*currentmon.stages[PBStats::SPATK] if currentmon.stages[PBStats::SPATK]>0 && specialmove
      noswitchscore+= (15)*currentmon.stages[PBStats::SPEED] if currentmon.stages[PBStats::SPEED]>0 unless (currentroles.include?(PBMonRoles::PHYSICALWALL) || currentroles.include?(PBMonRoles::SPECIALWALL) || currentroles.include?(PBMonRoles::TANK))
    end
    if currentroles.include?(PBMonRoles::PHYSICALWALL)
      noswitchscore+= (30)*currentmon.stages[PBStats::DEFENSE] if currentmon.stages[PBStats::DEFENSE]<0
    else
      noswitchscore+= (15)*currentmon.stages[PBStats::DEFENSE] if currentmon.stages[PBStats::DEFENSE]<0
    end
    if currentroles.include?(PBMonRoles::SPECIALWALL)
      noswitchscore+= (30)*currentmon.stages[PBStats::SPDEF] if currentmon.stages[PBStats::SPDEF]<0
    else
      noswitchscore+= (15)*currentmon.stages[PBStats::SPDEF] if currentmon.stages[PBStats::SPDEF]<0
    end
    # Entry Hazards
    PBDebug.log(sprintf("Initial noswitchscore building: Entry Hazards (%d)",noswitchscore)) if $INTERNAL
    noswitchscore+= (15)*currentmon.pbOwnSide.effects[PBEffects::Spikes]
    noswitchscore+= (15)*currentmon.pbOwnSide.effects[PBEffects::ToxicSpikes]
    noswitchscore+= (15) if currentmon.pbOwnSide.effects[PBEffects::StealthRock]
    noswitchscore+= (15) if currentmon.pbOwnSide.effects[PBEffects::StickyWeb]
    noswitchscore+= (15) if (currentmon.pbOwnSide.effects[PBEffects::StickyWeb] && currentroles.include?(PBMonRoles::SWEEPER))
    airmon = currentmon.isAirborne?
    hazarddam = totalHazardDamage(currentmon.pbOwnSide,currentmon.type1,currentmon.type2,airmon,skill)
    if ((currentmon.hp.to_f)/currentmon.totalhp)*100 < hazarddam
      noswitchscore+= 100
    end
    temppartyko = true
    for i in party
      count+=1
      next if i.nil?
      next if count == currentmon.pokemonIndex
      temproles = pbGetMonRole(i,opponent1,skill,count,party)
      next if temproles.include?(PBMonRoles::ACE)
      tempdam = totalHazardDamage(currentmon.pbOwnSide,i.type1,i.type2,i.isAirborne?,skill)
      if ((i.hp.to_f)/i.totalhp)*100 > tempdam
        temppartyko = false
      end
    end
    if temppartyko
      noswitchscore+= 200
    end
    # Better Switching Options
    PBDebug.log(sprintf("Initial noswitchscore building: Better Switching Options (%d)",noswitchscore)) if $INTERNAL
    if pbRoughStat(currentmon,PBStats::SPEED,skill) > pbRoughStat(opponent1,PBStats::SPEED,skill)
      if currentmon.pbHasMove?((PBMoves::VOLTSWITCH)) || currentmon.pbHasMove?((PBMoves::UTURN))
        noswitchscore+=90
      end
    end
    if currentmon.effects[PBEffects::PerishSong]==0 && currentmon.pbHasMove?((PBMoves::BATONPASS))
      noswitchscore+=90
    end
    if (!currentmon.abilitynulled && currentmon.ability == PBAbilities::WIMPOUT) || (!currentmon.abilitynulled && currentmon.ability == PBAbilities::EMERGENCYEXIT)
      noswitchscore+=60
    end
    # Second Wind Situations
    PBDebug.log(sprintf("Initial noswitchscore building: Second Wind Situations (%d)",noswitchscore)) if $INTERNAL
    if !checkAIpriority(aimem)
      if pbRoughStat(currentmon,PBStats::SPEED,skill) > pbRoughStat(opponent1,PBStats::SPEED,skill)
        maxdam = 0
        for i in currentmon.moves
          if opponent1.hp>0
            tempdam = (pbRoughDamage(i,opponent1,currentmon,skill,i.basedamage)*100/opponent1.hp)
          else
            tempdam=0
          end
          if tempdam > maxdam
            maxdam = tempdam
          end
        end
        if maxdam > 100
          noswitchscore+=130
        end
      end
      if pbRoughStat(currentmon,PBStats::SPEED,skill) > pbRoughStat(opponent2,PBStats::SPEED,skill)
        maxdam = 0
        for i in currentmon.moves
          if opponent2.hp>0
            tempdam = (pbRoughDamage(i,opponent2,currentmon,skill,i.basedamage)*100/opponent2.hp)
          else
            tempdam=0
          end
          if tempdam > maxdam
            maxdam = tempdam
          end
        end
        if maxdam > 100
          noswitchscore+=130
        end
      end
      maxdam = 0
      for i in currentmon.moves
        next if i.priority < 1
        if opponent1.hp>0
          tempdam = (pbRoughDamage(i,opponent1,currentmon,skill,i.basedamage)*100/opponent1.hp)
        else
          tempdam=0
        end
        if tempdam > maxdam
          maxdam = tempdam
        end
      end
      if maxdam > 100
        noswitchscore+=130
      end
      maxdam = 0
      for i in currentmon.moves
        next if i.priority < 1
        if opponent2.hp>0
          tempdam = (pbRoughDamage(i,opponent2,currentmon,skill,i.basedamage)*100/opponent2.hp)
        else
          tempdam=0
        end
        if tempdam > maxdam
          maxdam = tempdam
        end
      end
      if maxdam > 100
        noswitchscore+=130
      end
    end
    finalcrit = 0
    for i in currentmon.moves
      critrate1 = pbAICritRate(currentmon,opponent1,i)
      critrate2 = pbAICritRate(currentmon,opponent2,i)
      maxcrit = [critrate1,critrate2].max
      if finalcrit < maxcrit
        finalcrit = maxcrit
      end
    end
    if finalcrit == 1
      noswitchscore+=12.5
    elsif finalcrit == 2
      noswitchscore += 50
    elsif finalcrit == 3
      noswitchscore += 100
    end
    if currentmon.status==PBStatuses::SLEEP && currentmon.statusCount<3
      noswitchscore+=100
    end
    monturn = (100 - (currentmon.turncount*25))
    if currentroles.include?(PBMonRoles::LEAD)
      monturn /= 1.5
    end
    if monturn > 0
      noswitchscore+=monturn
    end
    PBDebug.log(sprintf("%s: initial noswitchscore: %d",PBSpecies.getName(@battlers[index].species),noswitchscore)) if $INTERNAL
    PBDebug.log(sprintf(" ")) if $INTERNAL
    PBDebug.log(sprintf("{")) if $INTERNAL
    PBDebug.log(sprintf(" ")) if $INTERNAL
    finalscore = switchscore - noswitchscore
    if skill<PBTrainerAI.highSkill
      finalscore/=2.0
    end
    if skill<PBTrainerAI.mediumSkill
      finalscore-=100
    end
    highscore = @scores.max
    PBDebug.log(sprintf("}")) if $INTERNAL
    PBDebug.log(sprintf(" ")) if $INTERNAL
    PBDebug.log(sprintf("%s: highest move score: %d",PBSpecies.getName(@battlers[index].species),highscore)) if $INTERNAL
    PBDebug.log(sprintf("%s: final switching score: %d",PBSpecies.getName(@battlers[index].species),finalscore)) if $INTERNAL
    if finalscore > highscore
      PBDebug.log(sprintf("%s < %d, will switch",highscore,finalscore)) if $INTERNAL
      PBDebug.log(sprintf(" ")) if $INTERNAL
      willswitch = true
    else
      PBDebug.log(sprintf("%s > %d, will not switch",highscore,finalscore)) if $INTERNAL
      PBDebug.log(sprintf(" ")) if $INTERNAL
      willswitch = false
    end
    if willswitch
      memmons = monarray.length
      if memmons>0
        counts = Hash.new(0)
        monarray.each do |mon|
          counts[mon] += 1
        end
        storedswitch = -1
        storednumber = -1
        tievar = false
        for i in counts.keys
          if counts[i] > storednumber
            storedswitch = i
            storednumber = counts[i]
            tievar = true
          elsif counts[i] == storednumber
            tievar=true
          end
        end
        if !tievar
          PBDebug.log(sprintf("Switching to %s",PBSpecies.getName(pbParty(currentmon)[storedswitch].species))) if $INTERNAL
          return pbRegisterSwitch(currentmon.index,storedswitch)
        else
          wallvar = false
          monindex = -1
          for i in counts.keys
            temparr = pbGetMonRole(party[i],opponent1,skill,count,party)
            if temparr.include?(PBMonRoles::PHYSICALWALL) || temparr.include?(PBMonRoles::SPECIALWALL)
              wallvar = true
              monindex = i
            end
          end
          if wallvar
            return pbRegisterSwitch(currentmon.index,monindex)
          else
            maxhpvar = -1
            chosenmon = -1
            for i in counts.keys
              temphp = party[i].hp
              if temphp > maxhpvar
                maxhpvar = temphp
                chosenmon = i
              end
            end
            return pbRegisterSwitch(currentmon.index,chosenmon)
          end
        end
      else
        switchindex = pbSwitchTo(currentmon,party,skill)
        if switchindex==-1
          return false
        end
        return pbRegisterSwitch(currentmon.index,switchindex)
      end
    else
      return false
    end
  end

  def pbSpeedChangingSwitch(mon,currentmon)
    speed = mon.speed
    #if @unburdened
    #  speed=speed*2
    #end
    if currentmon.pbOwnSide.effects[PBEffects::Tailwind]>0
      speed=speed*2
    end
    if (mon.ability == PBAbilities::SWIFTSWIM) && pbWeather==PBWeather::RAINDANCE && !(mon.item == PBItems::UTILITYUMBRELLA)
      speed=speed*2
    elsif ($fefieldeffect == 21 || $fefieldeffect == 22 || $fefieldeffect == 26) && (mon.ability == PBAbilities::SWIFTSWIM)
      speed=speed*2
    elsif $fefieldeffect == 21 || $fefieldeffect == 26
      if (!mon.hasType?(:WATER) && !(mon.ability == PBAbilities::SURGESURFER)) && !mon.isAirborne? 
        speed=(speed*0.5).floor
      end
    elsif $fefieldeffect == 22
      if (!mon.hasType?(:WATER) && !(mon.ability == PBAbilities::SWIFTSWIM) && !(mon.ability == PBAbilities::STEELWORKER))  
        speed=(speed*0.25).floor
      end
    end
    if (mon.ability == PBAbilities::SLUSHRUSH) && (pbWeather==PBWeather::HAIL ||
      $fefieldeffect==13 || $fefieldeffect==28)
      speed=speed*2
    end
    if (mon.ability == PBAbilities::SURGESURFER) && (($fefieldeffect == 1) ||
      ($fefieldeffect==18) || ($fefieldeffect==21) || ($fefieldeffect==22) ||
      ($fefieldeffect==26))
      speed=speed*2
    end
    if (mon.ability == PBAbilities::TELEPATHY) && $fefieldeffect==37
      speed=speed*2
    end
    if $fefieldeffect == 35 && !mon.isAirborne?
      speed=(speed*0.5).floor
    end
    if (mon.ability == PBAbilities::CHLOROPHYLL) &&
      (pbWeather==PBWeather::SUNNYDAY ||
      ($fefieldeffect == 33 && $fecounter > 2)) && !(mon.item == PBItems::UTILITYUMBRELLA)
      speed=speed*2
    end
    if (mon.ability == PBAbilities::SANDRUSH) &&
       (pbWeather==PBWeather::SANDSTORM ||
       $fefieldeffect == 12 || $fefieldeffect == 20)
      speed=speed*2
    end
    if (mon.ability == PBAbilities::QUICKFEET) && mon.status>0
      speed=(speed*1.5).floor
    end
    if (mon.item == PBItems::MACHOBRACE) ||
       (mon.item == PBItems::POWERWEIGHT) ||
       (mon.item == PBItems::POWERBRACER) ||
       (mon.item == PBItems::POWERBELT) ||
       (mon.item == PBItems::POWERANKLET) ||
       (mon.item == PBItems::POWERLENS) ||
       (mon.item == PBItems::POWERBAND)
      speed=(speed/2).floor
    end
    if (mon.item == PBItems::CHOICESCARF)
      speed=(speed*1.5).floor
    end
    if mon.item == PBItems::IRONBALL && mon.ability != PBAbilities::KLUTZ
      speed=(speed/2).floor
    end
    if mon.species == PBSpecies::DITTO && mon.item == PBItems::QUICKPOWDER
      speed=speed*2
    end
    if (mon.ability == PBAbilities::SLOWSTART)
      speed=(speed/2).floor
    end
    if mon.status==PBStatuses::PARALYSIS && !(mon.ability == PBAbilities::QUICKFEET)
      speed=(speed/2).floor
    end
    if currentmon.pbOwnSide.effects[PBEffects::StickyWeb] && !mon.isAirborne? &&  ($fefieldeffect != 15) && !(mon.ability == PBAbilities::WHITESMOKE) && !(mon.ability == PBAbilities::CLEARBODY) && !(mon.ability == PBAbilities::CONTRARY)
      speed=(speed*2/3).floor
    elsif currentmon.pbOwnSide.effects[PBEffects::StickyWeb] && !mon.isAirborne? &&  ($fefieldeffect == 15) && !(mon.ability == PBAbilities::WHITESMOKE) && !(mon.ability == PBAbilities::CLEARBODY) && !(mon.ability == PBAbilities::CONTRARY)
      speed=(speed*0.5).floor
    elsif currentmon.pbOwnSide.effects[PBEffects::StickyWeb] && !mon.isAirborne? &&  ($fefieldeffect != 15) && (mon.ability == PBAbilities::CONTRARY)
      speed=(speed*1.5).floor
    elsif currentmon.pbOwnSide.effects[PBEffects::StickyWeb] && !mon.isAirborne? &&  ($fefieldeffect == 15) && (mon.ability == PBAbilities::CONTRARY)
      speed=speed*2
    end
    speed = 1 if speed <= 0
    return speed
  end

  def pbSwitchTo(currentmon,party,skill)
    opponent1 = currentmon.pbOppositeOpposing
    opponent2 = opponent1.pbPartner
    opp1roles = pbGetMonRole(opponent1,currentmon,skill)
    opp2roles = pbGetMonRole(opponent2,currentmon,skill)
    aimem = getAIMemory(skill,opponent1.pokemonIndex)
    aimem2 = getAIMemory(skill,opponent2.pokemonIndex)
    if skill<PBTrainerAI.mediumSkill
      loop do
        @ranvar = rand(party.length)
        break if ((@ranvar != currentmon.pokemonIndex) && pbCanSwitchLax?(currentmon.index,@ranvar,false))
      end
      return @ranvar
    end
    scorearray = []
    supercount=-1
    #for i in party
    for loopdawoop in 0...party.length
      i = party[loopdawoop].clone rescue nil
      nonmegaform = i.clone rescue nil
      supercount+=1
      if i.nil?
        scorearray.push(-10000000)
        next
      end
      PBDebug.log(sprintf("Scoring for %s switching to: %s",PBSpecies.getName(currentmon.species),PBSpecies.getName(i.species))) if $INTERNAL
      if !pbCanSwitchLax?(currentmon.index,supercount,false)
        scorearray.push(-10000000)
        PBDebug.log(sprintf("Score: -10000000")) if $INTERNAL
        PBDebug.log(sprintf(" ")) if $INTERNAL
        next
      end
      theseRoles = pbGetMonRole(i,opponent1,skill,supercount,party)
      if theseRoles.include?(PBMonRoles::PHYSICALWALL) || theseRoles.include?(PBMonRoles::SPECIALWALL)
        wallvar = true
      else
        wallvar = false
      end
      monscore = 0
      if (i.ability == PBAbilities::IMPOSTER)
        if @doublebattle
          i = opponent2.pokemon
          monscore += 20*opponent2.stages[PBStats::ATTACK]
          monscore += 20*opponent2.stages[PBStats::SPATK]
          monscore += 20*opponent2.stages[PBStats::SPEED]
        else
          i = opponent1.pokemon
          monscore += 20*opponent1.stages[PBStats::ATTACK]
          monscore += 20*opponent1.stages[PBStats::SPATK]
          monscore += 20*opponent1.stages[PBStats::SPEED]
        end
      end
      #Don't switch to already inplay mon
      if currentmon.pokemonIndex == scorearray.length
        scorearray.push(-10000000)
        PBDebug.log(sprintf("Score: -10000000")) if $INTERNAL
        PBDebug.log(sprintf(" ")) if $INTERNAL
        next
      end
      if supercount==pbParty(currentmon.index).length-1 && $game_switches[1000]
        scorearray.push(-10000)
        PBDebug.log(sprintf("Score: -10000")) if $INTERNAL
        PBDebug.log(sprintf(" ")) if $INTERNAL
        next
      end
      if i.hp <= 0
        scorearray.push(-10000000)
        PBDebug.log(sprintf("Score: -10000000")) if $INTERNAL
        PBDebug.log(sprintf(" ")) if $INTERNAL
        next
      end
      sedamagevar = 0
      if pbCanMegaEvolveAI?(i,currentmon.index)
        i.makeMega
      end
      #speed changing
      i.speed = pbSpeedChangingSwitch(i,currentmon)
      nonmegaform.speed = pbSpeedChangingSwitch(nonmegaform,currentmon)
      sedamagevar = 0
      #Defensive
      if aimem.length > 0
        for j in aimem
          totalmod = j.pbTypeModifierNonBattler(j.type,opponent1,i)
          if totalmod > 4
            sedamagevar = j.basedamage if j.basedamage>sedamagevar
            if totalmod >= 16
              sedamagevar*=2
            end
            if j.type == opponent1.type1 || j.type == opponent1.type2
              sedamagevar*=1.5
            end
          end
        end
        monscore-=sedamagevar
      end
      immunevar = 0
      resistvar = 0
      bestresist = false
      bestimmune = false
      count = 0
      movedamages = []
      bestmoveindex = -1
      if aimem.length > 0 && skill>=PBTrainerAI.highSkill
        for j in aimem
          movedamages.push(j.basedamage)
        end
        if movedamages.length > 0
          bestmoveindex = movedamages.index(movedamages.max)
        end
        for j in aimem
          totalmod = j.pbTypeModifierNonBattler(j.type,opponent1,i)
          if bestmoveindex > -1
            if count == bestmoveindex
              if totalmod == 0
                bestimmune = true
              elsif totalmod == 1 || totalmod == 2
                bestresist = true
              end
            end
          end
          if totalmod == 0
            immunevar+=1
          elsif totalmod == 1 || totalmod == 2
            resistvar+=1
          end
          count+=1
        end
        if immunevar == 4
          if wallvar
            monscore+=300
          else
            monscore+=200
          end
        elsif bestimmune
          if wallvar
            monscore+=90
          else
            monscore+=60
          end
        end
        if immunevar+resistvar == 4 && immunevar!=4
          if wallvar
            monscore+=150
          else
            monscore+=100
          end
        elsif bestresist
          if wallvar
            monscore+=45
          else
            monscore+=30
          end
        end
      elsif aimem.length > 0
        for j in aimem
          totalmod = j.pbTypeModifierNonBattler(j.type,opponent1,i)
          if totalmod == 0
            bestimmune=true
          elsif totalmod == 1 || totalmod == 2
            bestresist=true
          end
        end
        if bestimmune
          if wallvar
            monscore+=90
          else
            monscore+=60
          end
        end
        if bestresist
          if wallvar
            monscore+=45
          else
            monscore+=30
          end
        end
      end
      otype1 = opponent1.type1
      otype2 = opponent1.type2
      otype3 = opponent2.type1
      otype4 = opponent2.type2
      atype1 = i.type1
      atype2 = i.type2
      stabresist1a = PBTypes.getEffectiveness(otype1,atype1)
      if atype1!=atype2
        stabresist1b = PBTypes.getEffectiveness(otype1,atype2)
      else
        stabresist1b = 2
      end
      stabresist2a = PBTypes.getEffectiveness(otype2,atype1)
      if atype1!=atype2
        stabresist2b = PBTypes.getEffectiveness(otype2,atype2)
      else
        stabresist2b = 2
      end
      stabresist3a = PBTypes.getEffectiveness(otype3,atype1)
      if atype1!=atype2
        stabresist3b = PBTypes.getEffectiveness(otype3,atype2)
      else
        stabresist3b = 2
      end
      stabresist4a = PBTypes.getEffectiveness(otype4,atype1)
      if atype1!=atype2
        stabresist4b = PBTypes.getEffectiveness(otype4,atype2)
      else
        stabresist4b = 2
      end
      if stabresist1a*stabresist1b<4 || stabresist2a*stabresist2b<4
        monscore+=40
        if otype1==otype2
          monscore+=30
        else
          if stabresist1a*stabresist1b<4 && stabresist2a*stabresist2b<4
            monscore+=60
          end
        end
      elsif stabresist1a*stabresist1b>4 || stabresist2a*stabresist2b>4
        monscore-=40
        if otype1==otype2
          monscore-=30
        else
          if stabresist1a*stabresist1b>4 && stabresist2a*stabresist2b>4
            monscore-=60
          end
        end
      end
      if stabresist3a*stabresist3b<4 || stabresist4a*stabresist4b<4
        monscore+=40
        if otype3==otype4
          monscore+=30
        else
          if stabresist3a*stabresist3b<4 && stabresist4a*stabresist4b<4
            monscore+=60
          end
        end
      elsif stabresist3a*stabresist3b>4 || stabresist4a*stabresist4b>4
        monscore-=40
        if otype3==otype4
          monscore-=30
        else
          if stabresist3a*stabresist3b>4 && stabresist4a*stabresist4b>4
            monscore-=60
          end
        end
      end
      PBDebug.log(sprintf("Defensive: %d",monscore)) if $INTERNAL
      # Offensive
      maxbasedam = -1
      bestmove = -1
      for k in i.moves
        j = PokeBattle_Move.new(self,k,i)
        basedam = j.basedamage
        if (j.pbTypeModifierNonBattler(j.type,i,opponent1)>4) || ((j.pbTypeModifierNonBattler(j.type,i,opponent2)>4) && opponent2.totalhp !=0)
          basedam*=2
          if (j.pbTypeModifierNonBattler(j.type,i,opponent1)==16) || ((j.pbTypeModifierNonBattler(j.type,i,opponent2)==16) && opponent2.totalhp !=0)
            basedam*=2
          end
        end
        if (j.pbTypeModifierNonBattler(j.type,i,opponent1)<4) || ((j.pbTypeModifierNonBattler(j.type,i,opponent2)<4) && opponent2.totalhp !=0)
          basedam/=2.0
          if (j.pbTypeModifierNonBattler(j.type,i,opponent1)==1) || ((j.pbTypeModifierNonBattler(j.type,i,opponent2)==1) && opponent2.totalhp !=0)
            basedam/=2.0
          end
        end
        if (j.pbTypeModifierNonBattler(j.type,i,opponent1)==0) || ((j.pbTypeModifierNonBattler(j.type,i,opponent2)==0) && opponent2.totalhp !=0)
          basedam=0
        end
        if (j.pbTypeModifierNonBattler(j.type,i,opponent1)<=4 && (!opponent1.abilitynulled && opponent1.ability == PBAbilities::WONDERGUARD)) || ((j.pbTypeModifierNonBattler(j.type,i,opponent2)<=4 && (!opponent2.abilitynulled && opponent2.ability == PBAbilities::WONDERGUARD)) && opponent2.totalhp !=0)
          basedam=0
        end
        if (((!opponent1.abilitynulled && opponent1.ability == PBAbilities::STORMDRAIN) || (!opponent2.abilitynulled && opponent2.ability == PBAbilities::STORMDRAIN) ||
          (!opponent1.abilitynulled && opponent1.ability == PBAbilities::WATERABSORB) || (!opponent2.abilitynulled && opponent2.ability == PBAbilities::WATERABSORB) ||
          (!opponent1.abilitynulled && opponent1.ability == PBAbilities::DRYSKIN) || (!opponent2.abilitynulled && opponent2.ability == PBAbilities::DRYSKIN)) &&
          (j.type == PBTypes::WATER)) ||
          (((!opponent1.abilitynulled && opponent1.ability == PBAbilities::VOLTABSORB) || (!opponent2.abilitynulled && opponent2.ability == PBAbilities::VOLTABSORB) ||
          (!opponent1.abilitynulled && opponent1.ability == PBAbilities::MOTORDRIVE) || (!opponent2.abilitynulled && opponent2.ability == PBAbilities::MOTORDRIVE)) &&
          (j.type == PBTypes::ELECTRIC)) ||
          (((!opponent1.abilitynulled && opponent1.ability == PBAbilities::FLASHFIRE) || (!opponent2.abilitynulled && opponent2.ability == PBAbilities::FLASHFIRE)) &&
          (j.type == PBTypes::FIRE)) ||
          (((!opponent1.abilitynulled && opponent1.ability == PBAbilities::SAPSIPPER) || (!opponent2.abilitynulled && opponent2.ability == PBAbilities::SAPSIPPER)) &&
          (j.type == PBTypes::GRASS))
          basedam=0
        end
        if j.pbIsPhysical?(j.type) && i.status==PBStatuses::BURN
          basedam/=2.0
        end
        if skill>=PBTrainerAI.highSkill
          if i.hasType?(j.type)
            basedam*=1.5
          end
        end
        if j.accuracy!=0
          basedam*=(j.accuracy/100.0)
        end
        if basedam>maxbasedam
          maxbasedam = basedam
          bestmove = j
        end
      end
      if bestmove!=-1
        if bestmove.priority>0
          maxbasedam*=1.5
        end
      end
      if i.speed<pbRoughStat(opponent1,PBStats::SPEED,skill) || i.speed<pbRoughStat(opponent2,PBStats::SPEED,skill)
        maxbasedam*=0.75
      else
        maxbasedam*=1.25
      end
      if maxbasedam==0
        monscore-=80
      else
        monscore+=maxbasedam
        ministat=0
        if i.attack > i.spatk
          ministat = [(opponent1.stages[PBStats::SPDEF] - opponent1.stages[PBStats::DEFENSE]),(opponent2.stages[PBStats::SPDEF] - opponent2.stages[PBStats::DEFENSE])].max
        else
          ministat = [(opponent1.stages[PBStats::DEFENSE] - opponent1.stages[PBStats::SPDEF]),(opponent1.stages[PBStats::DEFENSE] - opponent1.stages[PBStats::SPDEF])].max
        end
        ministat*=20
        monscore+=ministat
      end
      PBDebug.log(sprintf("Offensive: %d",monscore)) if $INTERNAL
      #Roles
      if skill>=PBTrainerAI.highSkill
        if theseRoles.include?(PBMonRoles::SWEEPER)
          if currentmon.pbNonActivePokemonCount<2
            monscore+=60
          else
            monscore-=50
          end
          if i.attack >= i.spatk
            if (opponent1.defense<opponent1.spdef) || (opponent2.defense<opponent2.spdef)
              monscore+=30
            end
          end
          if i.spatk >= i.attack
            if (opponent1.spdef<opponent1.defense) || (opponent2.spdef<opponent2.defense)
              monscore+=30
            end
          end
          monscore+= (-10)* statchangecounter(opponent1,1,7,-1)
          monscore+= (-10)* statchangecounter(opponent2,1,7,-1)
          if ((i.speed > opponent1.pbSpeed) ^ (@trickroom!=0))
            monscore *= 1.3
          else
            monscore *= 0.7
          end
          if opponent1.status==PBStatuses::SLEEP || opponent1.status==PBStatuses::FROZEN
            monscore+=50
          end
        end
        if wallvar
          if theseRoles.include?(PBMonRoles::PHYSICALWALL) && (opponent1.spatk>opponent1.attack || opponent2.spatk>opponent2.attack)
            monscore+=30
          end
          if theseRoles.include?(PBMonRoles::SPECIALWALL) && (opponent1.spatk<opponent1.attack || opponent2.spatk<opponent2.attack)
            monscore+=30
          end
          if opponent1.status==PBStatuses::BURN || opponent1.status==PBStatuses::POISON || opponent1.effects[PBEffects::LeechSeed]>0
            monscore+=30
          end
          if opponent2.status==PBStatuses::BURN || opponent2.status==PBStatuses::POISON || opponent2.effects[PBEffects::LeechSeed]>0
            monscore+=30
          end
        end
        if theseRoles.include?(PBMonRoles::TANK)
          if opponent1.status==PBStatuses::PARALYSIS || opponent1.effects[PBEffects::LeechSeed]>0
            monscore+=40
          end
          if opponent2.status==PBStatuses::PARALYSIS || opponent2.effects[PBEffects::LeechSeed]>0
            monscore+=40
          end
          if currentmon.pbOwnSide.effects[PBEffects::Tailwind]>0
            monscore+=30
          end
        end
        if theseRoles.include?(PBMonRoles::LEAD)
          monscore+=40
        end
        if theseRoles.include?(PBMonRoles::CLERIC)
          partystatus = false
          partymidhp = false
          for k in party
            next if k.nil?
            next if k==i
            next if k.totalhp==0
            if k.status!=0
              partystatus=true
            end
            if 0.3<((k.hp.to_f)/k.totalhp) && ((k.hp.to_f)/k.totalhp)<0.6
              partymidhp = true
            end
          end
          if partystatus
            monscore+=50
          end
          if partymidhp
            monscore+=50
          end
        end
        if theseRoles.include?(PBMonRoles::PHAZER)
          monscore+= (10)*opponent1.stages[PBStats::ATTACK] if opponent1.stages[PBStats::ATTACK]<0
          monscore+= (10)*opponent2.stages[PBStats::ATTACK] if opponent2.stages[PBStats::ATTACK]<0
          monscore+= (20)*opponent1.stages[PBStats::DEFENSE] if opponent1.stages[PBStats::DEFENSE]<0
          monscore+= (20)*opponent2.stages[PBStats::DEFENSE] if opponent2.stages[PBStats::DEFENSE]<0
          monscore+= (10)*opponent1.stages[PBStats::SPATK] if opponent1.stages[PBStats::SPATK]<0
          monscore+= (10)*opponent2.stages[PBStats::SPATK] if opponent2.stages[PBStats::SPATK]<0
          monscore+= (20)*opponent1.stages[PBStats::SPDEF] if opponent1.stages[PBStats::SPDEF]<0
          monscore+= (20)*opponent2.stages[PBStats::SPDEF] if opponent2.stages[PBStats::SPDEF]<0
          monscore+= (10)*opponent1.stages[PBStats::SPEED] if opponent1.stages[PBStats::SPEED]<0
          monscore+= (10)*opponent2.stages[PBStats::SPEED] if opponent2.stages[PBStats::SPEED]<0
          monscore+= (20)*opponent1.stages[PBStats::EVASION] if opponent1.stages[PBStats::ACCURACY]<0
          monscore+= (20)*opponent2.stages[PBStats::EVASION] if opponent2.stages[PBStats::ACCURACY]<0
        end
        if theseRoles.include?(PBMonRoles::SCREENER)
          monscore+=60
        end
        if theseRoles.include?(PBMonRoles::REVENGEKILLER)
          if opponent2.totalhp!=0 && opponent1.totalhp!=0
            if ((opponent1.hp.to_f)/opponent1.totalhp)<0.3 || ((opponent2.hp.to_f)/opponent2.totalhp)<0.3
              monscore+=110
            end
          elsif opponent1.totalhp!=0
            if ((opponent1.hp.to_f)/opponent1.totalhp)<0.3
              monscore+=110
            end
          elsif opponent2.totalhp!=0
            if ((opponent2.hp.to_f)/opponent2.totalhp)<0.3
              monscore+=110
            end
          end
        end
        if theseRoles.include?(PBMonRoles::SPINNER)
          if !opponent1.pbHasType?(:GHOST) && (opponent2.hp==0 || !opponent2.pbHasType?(:GHOST))
            monscore+=20*currentmon.pbOwnSide.effects[PBEffects::Spikes]
            monscore+=20*currentmon.pbOwnSide.effects[PBEffects::ToxicSpikes]
            monscore+=30 if currentmon.pbOwnSide.effects[PBEffects::StickyWeb]
            monscore+=30 if currentmon.pbOwnSide.effects[PBEffects::StealthRock]
          end
        end
        if theseRoles.include?(PBMonRoles::PIVOT)
          monscore+=40
        end
        if theseRoles.include?(PBMonRoles::BATONPASSER)
          monscore+=50
        end
        if theseRoles.include?(PBMonRoles::STALLBREAKER)
          monscore+=80 if checkAIhealing(aimem) || checkAIhealing(aimem2)
        end
        if theseRoles.include?(PBMonRoles::STATUSABSORBER)
          statusmove = false
          if aimem.length > 0
            for j in aimem
              statusmove=true if (j.id==(PBMoves::THUNDERWAVE) ||
              j.id==(PBMoves::TOXIC) || j.id==(PBMoves::SPORE) ||
              j.id==(PBMoves::SING) || j.id==(PBMoves::POISONPOWDER) ||
              j.id==(PBMoves::STUNSPORE) || j.id==(PBMoves::SLEEPPOWDER) ||
              j.id==(PBMoves::NUZZLE) || j.id==(PBMoves::WILLOWISP) ||
              j.id==(PBMoves::HYPNOSIS) || j.id==(PBMoves::GLARE) ||
              j.id==(PBMoves::DARKVOID) || j.id==(PBMoves::GRASSWHISTLE) ||
              j.id==(PBMoves::LOVELYKISS) || j.id==(PBMoves::POISONGAS) ||
              j.id==(PBMoves::TOXICTHREAD))
            end
          end
          if skill>=PBTrainerAI.bestSkill && aimem2.length!=0
            for j in aimem2
              statusmove=true if (j.id==(PBMoves::THUNDERWAVE) ||
              j.id==(PBMoves::TOXIC) || j.id==(PBMoves::SPORE) ||
              j.id==(PBMoves::SING) || j.id==(PBMoves::POISONPOWDER) ||
              j.id==(PBMoves::STUNSPORE) || j.id==(PBMoves::SLEEPPOWDER) ||
              j.id==(PBMoves::NUZZLE) || j.id==(PBMoves::WILLOWISP) ||
              j.id==(PBMoves::HYPNOSIS) || j.id==(PBMoves::GLARE) ||
              j.id==(PBMoves::DARKVOID) || j.id==(PBMoves::GRASSWHISTLE) ||
              j.id==(PBMoves::LOVELYKISS) || j.id==(PBMoves::POISONGAS) ||
              j.id==(PBMoves::TOXICTHREAD))
            end
          end
          monscore+=70 if statusmove
        end
        if theseRoles.include?(PBMonRoles::TRAPPER)
          if ((i.speed>opponent1.pbSpeed) ^ (@trickroom!=0))
            if opponent1.totalhp!=0
              if (opponent1.hp.to_f)/opponent1.totalhp<0.6
                monscore+=100
              end
            end
          end
        end
        if theseRoles.include?(PBMonRoles::WEATHERSETTER)
          monscore+=30
          if (i.ability == PBAbilities::DROUGHT) || (nonmegaform.ability == PBAbilities::DROUGHT) || i.knowsMove?(:SUNNYDAY)
            if @weather!=PBWeather::SUNNYDAY
              monscore+=60
            end
          elsif (i.ability == PBAbilities::DRIZZLE) || (nonmegaform.ability == PBAbilities::DRIZZLE) || i.knowsMove?(:RAINDANCE)
            if @weather!=PBWeather::RAINDANCE
              monscore+=60
            end
          elsif (i.ability == PBAbilities::SANDSTREAM) || (nonmegaform.ability == PBAbilities::SANDSTREAM) || i.knowsMove?(:SANDSTORM)
            if @weather!=PBWeather::SANDSTORM
              monscore+=60
            end
          elsif (i.ability == PBAbilities::SNOWWARNING) || (nonmegaform.ability == PBAbilities::SNOWWARNING) || i.knowsMove?(:HAIL)
            if @weather!=PBWeather::HAIL
              monscore+=60
            end
          elsif (i.ability == PBAbilities::PRIMORDIALSEA) || (i.ability == PBAbilities::DESOLATELAND) || (i.ability == PBAbilities::DELTASTREAM) ||
            (nonmegaform.ability == PBAbilities::PRIMORDIALSEA) || (nonmegaform.ability == PBAbilities::DESOLATELAND) || (nonmegaform.ability == PBAbilities::DELTASTREAM) ||
            monscore+=60
          end
        end
      #  if theseRoles.include?(PBMonRoles::SECOND)
     #     monscore-=40
        #end
      end
      PBDebug.log(sprintf("Roles: %d",monscore)) if $INTERNAL
      # Weather
      case @weather
        when PBWeather::HAIL
          monscore+=25 if (i.ability == PBAbilities::MAGICGUARD) || (i.ability == PBAbilities::OVERCOAT) || i.hasType?(:ICE)
          monscore+=50 if (i.ability == PBAbilities::SNOWCLOAK) || (i.ability == PBAbilities::ICEBODY)
          monscore+=80 if (i.ability == PBAbilities::SLUSHRUSH)
        when PBWeather::RAINDANCE
            monscore+=50 if (i.ability == PBAbilities::DRYSKIN) || (i.ability == PBAbilities::HYDRATION) || (i.ability == PBAbilities::RAINDISH)
            monscore+=80 if (i.ability == PBAbilities::SWIFTSWIM)
        when PBWeather::SUNNYDAY
          monscore-=40 if (i.ability == PBAbilities::DRYSKIN)
          monscore+=50 if (i.ability == PBAbilities::SOLARPOWER)
          monscore+=80 if (i.ability == PBAbilities::CHLOROPHYLL)
        when PBWeather::SANDSTORM
          monscore+=25 if (i.ability == PBAbilities::MAGICGUARD) || (i.ability == PBAbilities::OVERCOAT) || i.hasType?(:ROCK) || i.hasType?(:GROUND) || i.hasType?(:STEEL)
          monscore+=50 if (i.ability == PBAbilities::SANDVEIL) || (i.ability == PBAbilities::SANDFORCE)
          monscore+=80 if (i.ability == PBAbilities::SANDRUSH)
      end
      if @trickroom>0
        if i.speed<opponent1.pbSpeed
          monscore+=30
        else
          monscore-=30
        end
        if opponent2.totalhp > 0
          if i.speed<opponent2.pbSpeed
            monscore+=30
          else
            monscore-=30
          end
        end
      end
      PBDebug.log(sprintf("Weather: %d",monscore)) if $INTERNAL
      #Moves
      if skill>=PBTrainerAI.highSkill
        if currentmon.pbOwnSide.effects[PBEffects::ToxicSpikes] > 0
          if nonmegaform.hasType?(:POISON) && !nonmegaform.hasType?(:FLYING) && !(nonmegaform.ability == PBAbilities::LEVITATE)
            monscore+=80
          end
          if nonmegaform.hasType?(:FLYING) || nonmegaform.hasType?(:STEEL) || (nonmegaform.ability == PBAbilities::LEVITATE)
            monscore+=30
          end
        end
        if i.knowsMove?(:CLEARSMOG) || i.knowsMove?(:HAZE)
          monscore+= (10)* statchangecounter(opponent1,1,7,1)
          monscore+= (10)* statchangecounter(opponent2,1,7,1)
        end
        if i.knowsMove?(:FAKEOUT) || i.knowsMove?(:FIRSTIMPRESSION)
          monscore+=25
        end
        if currentmon.pbPartner.totalhp != 0
          if i.knowsMove?(:FUSIONBOLT) && currentmon.pbPartner.pbHasMove?((PBMoves::FUSIONFLARE))
            monscore+=70
          end
          if i.knowsMove?(:FUSIONFLARE) && currentmon.pbPartner.pbHasMove?((PBMoves::FUSIONBOLT))
            monscore+=70
          end
        end
        if i.knowsMove?(:RETALIATE) && currentmon.pbOwnSide.effects[PBEffects::Retaliate]
          monscore+=30
        end
        if opponent1.totalhp>0
          if i.knowsMove?(:FELLSTINGER) && (((i.speed>opponent1.pbSpeed) ^ (@trickroom!=0)) && (opponent1.hp.to_f)/opponent1.totalhp<0.2)
            monscore+=50
          end
        end
        if opponent2.totalhp>0
          if i.knowsMove?(:FELLSTINGER) && (((i.speed>opponent2.pbSpeed) ^ (@trickroom!=0)) && (opponent2.hp.to_f)/opponent2.totalhp<0.2)
            monscore+=50
          end
        end
        if i.knowsMove?(:TAILWIND)
          if currentmon.pbOwnSide.effects[PBEffects::Tailwind]>0
            monscore-=60
          else
            monscore+=30
          end
        end
        if i.knowsMove?(:PURSUIT) || i.knowsMove?(:SANDSTORM) || i.knowsMove?(:HAIL) ||
         i.knowsMove?(:TOXIC) || i.knowsMove?(:LEECHSEED)
          monscore+=70 if (opponent1.ability == PBAbilities::WONDERGUARD)
          monscore+=70 if (opponent2.ability == PBAbilities::WONDERGUARD)
        end
      end
      PBDebug.log(sprintf("Moves: %d",monscore)) if $INTERNAL
      #Abilities
      if skill>=PBTrainerAI.highSkill
        if (i.ability == PBAbilities::UNAWARE)
          monscore+= (10)* statchangecounter(opponent1,1,7,1)
          monscore+= (10)* statchangecounter(opponent2,1,7,1)
        end
        if (i.ability == PBAbilities::DROUGHT) || (i.ability == PBAbilities::DESOLATELAND) || (nonmegaform.ability == PBAbilities::DROUGHT) || (nonmegaform.ability == PBAbilities::DESOLATELAND)
          monscore+=40 if opponent1.pbHasType?(:WATER)
          monscore+=40 if opponent2.pbHasType?(:WATER)
          typecheck=false
          if aimem.length!=0
            for j in aimem
              if (j.type == PBTypes::WATER)
                typecheck=true
              end
            end
            monscore+=15 if typecheck
          end
          if aimem2.length!=0 && skill>=PBTrainerAI.bestSkill
            for j in aimem2
              if (j.type == PBTypes::WATER)
                typecheck=true
              end
            end
            monscore+=15 if typecheck
          end
        end
        if (i.ability == PBAbilities::DRIZZLE) || (i.ability == PBAbilities::PRIMORDIALSEA) || (nonmegaform.ability == PBAbilities::DRIZZLE) || (nonmegaform.ability == PBAbilities::PRIMORDIALSEA)
          monscore+=40 if opponent1.pbHasType?(:FIRE)
          monscore+=40 if opponent2.pbHasType?(:FIRE)
          typecheck=false
          if aimem.length!=0
            for j in aimem
              if (j.type == PBTypes::FIRE)
                typecheck=true
              end
            end
            monscore+=15 if typecheck
          end
          if aimem2.length!=0 && skill>=PBTrainerAI.bestSkill
            for j in aimem2
              if (j.type == PBTypes::FIRE)
                typecheck=true
              end
            end
            monscore+=15 if typecheck
          end
        end
        if (i.ability == PBAbilities::LIMBER)
          if aimem.length!=0
            monscore+=15 if checkAImoves(PBStuff::PARAMOVE,aimem)
          end
          if aimem2.length!=0 && skill>=PBTrainerAI.bestSkill
            monscore+=15 if checkAImoves(PBStuff::PARAMOVE,aimem2)
          end
        end
        if (i.ability == PBAbilities::OBLIVIOUS)
          monscore+=20 if (opponent1.ability == PBAbilities::CUTECHARM) || (opponent2.ability == PBAbilities::CUTECHARM)
          if aimem.length!=0
            monscore+=20 if checkAImoves([PBMoves::ATTRACT],aimem)
          end
          if aimem2.length!=0 && skill>=PBTrainerAI.bestSkill
            monscore+=20 if checkAImoves([PBMoves::ATTRACT],aimem2)
          end
        end
        if (i.ability == PBAbilities::COMPOUNDEYES)
          if (opponent1.item == PBItems::LAXINCENSE) || (opponent1.item == PBItems::BRIGHTPOWDER) || opponent1.stages[PBStats::EVASION]>0 || ((opponent1.ability == PBAbilities::SANDVEIL) && @weather==PBWeather::SANDSTORM) || ((opponent1.ability == PBAbilities::SNOWCLOAK) && @weather==PBWeather::HAIL)
            monscore+=25
          end
          if (opponent2.item == PBItems::LAXINCENSE) || (opponent2.item == PBItems::BRIGHTPOWDER) || opponent2.stages[PBStats::EVASION]>0 || ((opponent2.ability == PBAbilities::SANDVEIL) && @weather==PBWeather::SANDSTORM) || ((opponent2.ability == PBAbilities::SNOWCLOAK) && @weather==PBWeather::HAIL)
            monscore+=25
          end
        end
        if (i.ability == PBAbilities::COMATOSE)
          monscore+=20 if checkAImoves(PBStuff::BURNMOVE,aimem)
          monscore+=20 if checkAImoves(PBStuff::PARAMOVE,aimem)
          monscore+=20 if checkAImoves(PBStuff::SLEEPMOVE,aimem)
          monscore+=20 if checkAImoves(PBStuff::POISONMOVE,aimem)
        end
        if (i.ability == PBAbilities::INSOMNIA) || (i.ability == PBAbilities::VITALSPIRIT)
          monscore+=20 if checkAImoves(PBStuff::SLEEPMOVE,aimem)
        end
        if (i.ability == PBAbilities::POISONHEAL) || (i.ability == PBAbilities::TOXICBOOST) || (i.ability == PBAbilities::IMMUNITY)
          monscore+=20 if checkAImoves(PBStuff::POISONMOVE,aimem)
        end
        if (i.ability == PBAbilities::MAGICGUARD)
          monscore+=20 if checkAImoves([PBMoves::LEECHSEED],aimem)
          monscore+=20 if checkAImoves([PBMoves::WILLOWISP],aimem)
          monscore+=20 if checkAImoves(PBStuff::POISONMOVE,aimem)
        end
        if (i.ability == PBAbilities::WATERBUBBLE) || (i.ability == PBAbilities::WATERVEIL) || (i.ability == PBAbilities::FLAREBOOST)
          if checkAImoves([PBMoves::WILLOWISP],aimem)
            monscore+=10
            if (i.ability == PBAbilities::FLAREBOOST)
              monscore+=10
            end
          end
        end
        if (i.ability == PBAbilities::OWNTEMPO)
          monscore+=20 if checkAImoves(PBStuff::CONFUMOVE,aimem)
        end
        if (i.ability == PBAbilities::INTIMIDATE) || (nonmegaform.ability == PBAbilities::INTIMIDATE) || (i.ability == PBAbilities::FURCOAT) || (i.ability == PBAbilities::STAMINA)
          if opponent1.attack>opponent1.spatk
            monscore+=40
          end
          if opponent2.attack>opponent2.spatk
            monscore+=40
          end
        end
        if (i.ability == PBAbilities::WONDERGUARD)
          dievar = false
          instantdievar=false
          if aimem.length!=0
            for j in aimem
              if (j.type == PBTypes::FIRE) || (j.type == PBTypes::GHOST) || (j.type == PBTypes::DARK) || (j.type == PBTypes::ROCK) || (j.type == PBTypes::FLYING)
                dievar=true
              end
            end
          end
          if aimem2.length!=0 && skill>=PBTrainerAI.bestSkill
            for j in aimem2
              if (j.type == PBTypes::FIRE) || (j.type == PBTypes::GHOST) || (j.type == PBTypes::DARK) || (j.type == PBTypes::ROCK) || (j.type == PBTypes::FLYING)
                dievar=true
              end
            end
          end
          if @weather==PBWeather::HAIL || PBWeather::SANDSTORM
            dievar=true
            instantdievar=true
          end
          if i.status==PBStatuses::BURN || i.status==PBStatuses::POISON
            dievar=true
            instantdievar=true
          end
          if currentmon.pbOwnSide.effects[PBEffects::StealthRock] || currentmon.pbOwnSide.effects[PBEffects::Spikes]>0 || currentmon.pbOwnSide.effects[PBEffects::ToxicSpikes]>0
            dievar=true
            instantdievar=true
          end
          if (opponent1.ability == PBAbilities::MOLDBREAKER) || (opponent1.ability == PBAbilities::TURBOBLAZE) || (opponent1.ability == PBAbilities::TERAVOLT)
            dievar=true
          end
          if (opponent2.ability == PBAbilities::MOLDBREAKER) || (opponent2.ability == PBAbilities::TURBOBLAZE) || (opponent2.ability == PBAbilities::TERAVOLT)
            dievar=true
          end
          monscore+=90 if !dievar
          monscore-=90 if instantdievar
        end
        if (i.ability == PBAbilities::EFFECTSPORE) || (i.ability == PBAbilities::STATIC) || (i.ability == PBAbilities::POISONPOINT) || (i.ability == PBAbilities::ROUGHSKIN) || (i.ability == PBAbilities::IRONBARBS) || (i.ability == PBAbilities::FLAMEBODY) || (i.ability == PBAbilities::CUTECHARM) || (i.ability == PBAbilities::MUMMY) || (i.ability == PBAbilities::AFTERMATH) || (i.ability == PBAbilities::GOOEY) || ((i.ability == PBAbilities::FLUFFY) && (!opponent1.pbHasType?(PBTypes::FIRE) && !opponent2.pbHasType?(PBTypes::FIRE)))
          monscore+=30 if checkAIbest(aimem,4) || checkAIbest(aimem2,4)
        end
        if (i.ability == PBAbilities::TRACE)
          if (opponent1.ability == PBAbilities::WATERABSORB) ||
            (opponent1.ability == PBAbilities::VOLTABSORB) ||
            (opponent1.ability == PBAbilities::STORMDRAIN) ||
            (opponent1.ability == PBAbilities::MOTORDRIVE) ||
            (opponent1.ability == PBAbilities::FLASHFIRE) ||
            (opponent1.ability == PBAbilities::LEVITATE) ||
            (opponent1.ability == PBAbilities::LIGHTNINGROD) ||
            (opponent1.ability == PBAbilities::SAPSIPPER) ||
            (opponent1.ability == PBAbilities::DRYSKIN) ||
            (opponent1.ability == PBAbilities::SLUSHRUSH) ||
            (opponent1.ability == PBAbilities::SANDRUSH) ||
            (opponent1.ability == PBAbilities::SWIFTSWIM) ||
            (opponent1.ability == PBAbilities::CHLOROPHYLL) ||
            (opponent1.ability == PBAbilities::SPEEDBOOST) ||
            (opponent1.ability == PBAbilities::WONDERGUARD) ||
            (opponent1.ability == PBAbilities::PRANKSTER) ||
            (i.speed>opponent1.pbSpeed && ((opponent1.ability == PBAbilities::ADAPTABILITY) || (opponent1.ability == PBAbilities::DOWNLOAD) || (opponent1.ability == PBAbilities::PROTEAN))) ||
            (opponent1.attack>opponent1.spatk && (opponent1.ability == PBAbilities::INTIMIDATE)) ||
            (opponent1.ability == PBAbilities::UNAWARE) ||
            (i.hp==i.totalhp && ((opponent1.ability == PBAbilities::MULTISCALE) || (opponent1.ability == PBAbilities::SHADOWSHIELD)))
            monscore+=60
          end
        end
        if (i.ability == PBAbilities::MAGMAARMOR)
          typecheck=false
          if aimem.length!=0
            for j in aimem
              if (j.type == PBTypes::ICE)
                typecheck=true
              end
            end
            monscore+=20 if typecheck
          end
          if aimem2.length!=0 && skill>=PBTrainerAI.bestSkill
            for j in aimem2
              if (j.type == PBTypes::ICE)
                typecheck=true
              end
            end
            monscore+=20 if typecheck
          end
        end
        if (i.ability == PBAbilities::SOUNDPROOF)
          monscore+=60 if checkAIbest(aimem,5) || checkAIbest(aimem2,5)
        end
        if (i.ability == PBAbilities::THICKFAT)
          monscore+=30 if checkAIbest(aimem,1,[PBTypes::ICE,PBTypes::FIRE]) || checkAIbest(aimem2,1,[PBTypes::ICE,PBTypes::FIRE])
        end
        if (i.ability == PBAbilities::WATERBUBBLE)
          monscore+=30 if checkAIbest(aimem,1,[PBTypes::FIRE]) || checkAIbest(aimem2,1,[PBTypes::FIRE])
        end
        if (i.ability == PBAbilities::LIQUIDOOZE)
          if aimem.length!=0
            for j in aimem
              monscore+=40 if  j.id==(PBMoves::LEECHSEED) || j.function==0xDD || j.function==0x139 || j.function==0x158
            end
          end
        end
        if (i.ability == PBAbilities::RIVALRY)
          if i.gender==opponent1.gender
            monscore+=30
          end
          if i.gender==opponent2.gender
            monscore+=30
          end
        end
        if (i.ability == PBAbilities::SCRAPPY)
          if opponent1.pbHasType?(PBTypes::GHOST)
            monscore+=30
          end
          if opponent2.pbHasType?(PBTypes::GHOST)
            monscore+=30
          end
        end
        if (i.ability == PBAbilities::LIGHTMETAL)
          monscore+=10 if checkAImoves([PBMoves::GRASSKNOT,PBMoves::LOWKICK],aimem)
        end
        if (i.ability == PBAbilities::ANALYTIC)
          if ((i.speed<opponent1.pbSpeed) ^ (@trickroom!=0))
            monscore+=30
          end
          if ((i.speed<opponent2.pbSpeed) ^ (@trickroom!=0))
            monscore+=30
          end
        end
        if (i.ability == PBAbilities::ILLUSION)
          monscore+=40
        end
        if (i.ability == PBAbilities::IMPOSTER)
          monscore+= (20)*opponent1.stages[PBStats::ATTACK]
          monscore+= (20)*opponent1.stages[PBStats::SPATK]
          monscore+=50 if (opponent1.ability == PBAbilities::PUREPOWER) || (opponent1.ability == PBAbilities::HUGEPOWER) || (opponent1.ability == PBAbilities::MOXIE) || (opponent1.ability == PBAbilities::SPEEDBOOST) || (opponent1.ability == PBAbilities::BEASTBOOST) || (opponent1.ability == PBAbilities::SOULHEART) || (opponent1.ability == PBAbilities::WONDERGUARD) || (opponent1.ability == PBAbilities::PROTEAN)
          monscore+=30 if (opponent1.level>i.level) || opp1roles.include?(PBMonRoles::SWEEPER)
          if opponent.effects[PBEffects::Substitute] > 0
            monscore = -200
          end
          if opponent1.species != PBSpecies::DITTO
            monscore = -500
          end
        end
        if (i.ability == PBAbilities::MOXIE) || (i.ability == PBAbilities::BEASTBOOST) || (i.ability == PBAbilities::SOULHEART)
          if opponent1.totalhp!=0
            monscore+=40 if ((i.speed>opponent1.pbSpeed) ^ (@trickroom!=0)) && ((opponent1.hp.to_f)/opponent1.totalhp<0.5)
          end
          if @doublebattle && opponent2.totalhp!=0
            monscore+=40 if ((i.speed>opponent2.pbSpeed) ^ (@trickroom!=0)) && ((opponent2.hp.to_f)/opponent2.totalhp<0.5)
          end
        end
        if (i.ability == PBAbilities::SPEEDBOOST)
          if opponent1.totalhp!=0
            monscore+=25 if (i.speed>opponent1.pbSpeed) && ((opponent1.hp.to_f)/opponent1.totalhp<0.3)
          end
          if @doublebattle && opponent2.totalhp!=0
            monscore+=25 if (i.speed>opponent2.pbSpeed) && ((opponent2.hp.to_f)/opponent2.totalhp<0.3)
          end
        end
        if (i.ability == PBAbilities::JUSTIFIED)
          monscore+=30 if checkAIbest(aimem,1,[PBTypes::DARK]) || checkAIbest(aimem2,1,[PBTypes::DARK])
        end
        if (i.ability == PBAbilities::RATTLED)
          monscore+=15 if checkAIbest(aimem,1,[PBTypes::DARK,PBTypes::GHOST,PBTypes::BUG]) || checkAIbest(aimem2,1,[PBTypes::DARK,PBTypes::GHOST,PBTypes::BUG])
        end
        if (i.ability == PBAbilities::IRONBARBS) || (i.ability == PBAbilities::ROUGHSKIN)
          monscore+=30 if (opponent1.ability == PBAbilities::SKILLLINK)
          monscore+=30 if (opponent2.ability == PBAbilities::SKILLLINK)
        end
        if (i.ability == PBAbilities::PRANKSTER)
          monscore+=50 if ((opponent1.pbSpeed>i.speed) ^ (@trickroom!=0)) && !opponent1.pbHasType?(PBTypes::DARK)
          monscore+=50 if ((opponent2.pbSpeed>i.speed) ^ (@trickroom!=0)) && !opponent2.pbHasType?(PBTypes::DARK)
        end
        if (i.ability == PBAbilities::GALEWINGS)
          monscore+=50 if ((opponent1.pbSpeed>i.speed) ^ (@trickroom!=0)) && i.hp==i.totalhp && !currentmon.pbOwnSide.effects[PBEffects::StealthRock]
          monscore+=50 if ((opponent2.pbSpeed>i.speed) ^ (@trickroom!=0)) && i.hp==i.totalhp && !currentmon.pbOwnSide.effects[PBEffects::StealthRock]
        end
        if (i.ability == PBAbilities::BULLETPROOF)
          monscore+=60 if checkAIbest(aimem,6) || checkAIbest(aimem2,6)
        end
        if (i.ability == PBAbilities::AURABREAK)
          monscore+=50 if (opponent1.ability == PBAbilities::FAIRYAURA) || (opponent1.ability == PBAbilities::DARKAURA)
          monscore+=50 if (opponent2.ability == PBAbilities::FAIRYAURA) || (opponent2.ability == PBAbilities::DARKAURA)
        end
        if (i.ability == PBAbilities::PROTEAN)
          monscore+=40 if ((i.speed>opponent1.pbSpeed) ^ (@trickroom!=0)) || ((i.speed>opponent2.pbSpeed) ^ (@trickroom!=0))
        end
        if (i.ability == PBAbilities::DANCER)
          monscore+=30 if checkAImoves(PBStuff::DANCEMOVE,aimem)
          monscore+=30 if checkAImoves(PBStuff::DANCEMOVE,aimem2) && skill>=PBTrainerAI.bestSkill
        end
        if (i.ability == PBAbilities::MERCILESS)
          if opponent1.status==PBStatuses::POISON || opponent2.status==PBStatuses::POISON
            monscore+=50
          end
        end
        if (i.ability == PBAbilities::DAZZLING) || (i.ability == PBAbilities::QUEENLYMAJESTY)
          monscore+=20 if checkAIpriority(aimem)
          monscore+=20 if checkAIpriority(aimem2) && skill>=PBTrainerAI.bestSkill
        end
        if (i.ability == PBAbilities::SANDSTREAM) || (i.ability == PBAbilities::SNOWWARNING) || (nonmegaform.ability == PBAbilities::SANDSTREAM) || (nonmegaform.ability == PBAbilities::SNOWWARNING)
          monscore+=70 if (opponent1.ability == PBAbilities::WONDERGUARD)
          monscore+=70 if (opponent2.ability == PBAbilities::WONDERGUARD)
        end
        if (i.ability == PBAbilities::DEFEATIST)
          if currentmon.hp != 0 # hard switch
            monscore -= 80
          end
        end
        if (i.ability == PBAbilities::STURDY) && i.hp == i.totalhp
          if currentmon.hp != 0 # hard switch
            monscore -= 80
          end
        end
      end
      PBDebug.log(sprintf("Abilities: %d",monscore)) if $INTERNAL
      #Items
      if skill>=PBTrainerAI.highSkill
        if (i.item == PBItems::ROCKYHELMET)
          monscore+=30 if (opponent1.ability == PBAbilities::SKILLLINK)
          monscore+=30 if (opponent2.ability == PBAbilities::SKILLLINK)
          monscore+=30 if checkAIbest(aimem,4) || checkAIbest(aimem2,4)
        end
        if (i.item == PBItems::AIRBALLOON)
          allground=true
          biggestpower=0
          groundcheck=false
          if aimem.length!=0
            for j in aimem
              if !(j.type == PBTypes::GROUND)
                allground=false
              end
            end
          end
          if aimem2.length!=0 && skill>=PBTrainerAI.bestSkill
            for j in aimem2
              if !(j.type == PBTypes::GROUND)
                allground=false
              end
            end
          end
          monscore+=60 if checkAIbest(aimem,1,[PBTypes::GROUND]) || checkAIbest(aimem2,1,[PBTypes::GROUND])
          monscore+=100 if allground
        end
        if (i.item == PBItems::FLOATSTONE)
          monscore+=10 if checkAImoves([PBMoves::LOWKICK,PBMoves::GRASSKNOT],aimem)
        end
        if (i.item == PBItems::DESTINYKNOT)
          monscore+=20 if (opponent1.ability == PBAbilities::CUTECHARM)
          monscore+=20 if checkAImoves([PBMoves::ATTRACT],aimem)
        end
        if (i.item == PBItems::ABSORBBULB)
          monscore+=25 if checkAIbest(aimem,1,[PBTypes::WATER]) || checkAIbest(aimem2,1,[PBTypes::WATER])
        end
        if (i.item == PBItems::CELLBATTERY)
          monscore+=25 if checkAIbest(aimem,1,[PBTypes::ELECTRIC]) || checkAIbest(aimem2,1,[PBTypes::ELECTRIC])
        end
        if (((i.item == PBItems::FOCUSSASH) || ((i.ability == PBAbilities::STURDY)))) && i.hp == i.totalhp
          if @weather==PBWeather::SANDSTORM || @weather==PBWeather::HAIL ||
            currentmon.pbOwnSide.effects[PBEffects::StealthRock] ||
            currentmon.pbOwnSide.effects[PBEffects::Spikes]>0 ||
            currentmon.pbOwnSide.effects[PBEffects::ToxicSpikes]>0
            monscore-=30
          end
          if currentmon.hp != 0 # hard switch
            monscore -= 80
          end
          monscore+= (30)*opponent1.stages[PBStats::ATTACK]
          monscore+= (30)*opponent1.stages[PBStats::SPATK]
          monscore+= (30)*opponent1.stages[PBStats::SPEED]
        end
        if (i.item == PBItems::SNOWBALL)
          monscore+=25 if checkAIbest(aimem,1,[PBTypes::ICE]) || checkAIbest(aimem2,1,[PBTypes::ICE])
        end
        if (i.item == PBItems::PROTECTIVEPADS)
          if (i.ability == PBAbilities::EFFECTSPORE) || (i.ability == PBAbilities::STATIC) || (i.ability == PBAbilities::POISONPOINT) || (i.ability == PBAbilities::ROUGHSKIN) || (i.ability == PBAbilities::IRONBARBS) || (i.ability == PBAbilities::FLAMEBODY) || (i.ability == PBAbilities::CUTECHARM) || (i.ability == PBAbilities::MUMMY) || (i.ability == PBAbilities::AFTERMATH) || (i.ability == PBAbilities::GOOEY) || ((i.ability == PBAbilities::FLUFFY) && (!opponent1.pbHasType?(PBTypes::FIRE) && !opponent2.pbHasType?(PBTypes::FIRE))) || (opponent1.item == PBItems::ROCKYHELMET)
            monscore+=25
          end
        end
      end
      PBDebug.log(sprintf("Items: %d",monscore)) if $INTERNAL
      #Fields
      if skill>=PBTrainerAI.bestSkill
        case $fefieldeffect
          when 1
            monscore+=50 if (i.ability == PBAbilities::SURGESURFER)
            monscore+=25 if (i.ability == PBAbilities::GALVANIZE)
            monscore+=25 if i.hasType?(:ELECTRIC)
          when 2
            monscore+=30 if (i.ability == PBAbilities::GRASSPELT)
            monscore+=25 if i.hasType?(:GRASS) || i.hasType?(:FIRE)
          when 3
            monscore+=20 if i.hasType?(:FAIRY)
            monscore+=20 if (i.ability == PBAbilities::MARVELSCALE)
            monscore+=20 if (i.ability == PBAbilities::DRYSKIN)
            monscore+=20 if (i.ability == PBAbilities::WATERCOMPACTION)
            monscore+=25 if (i.ability == PBAbilities::PIXILATE)
            monscore+=25 if (i.ability == PBAbilities::SOULHEART)
          when 4
            monscore+=30 if (i.ability == PBAbilities::PRISMARMOR)
            monscore+=30 if (i.ability == PBAbilities::SHADOWSHIELD)
          when 5
            monscore+=10 if (i.ability == PBAbilities::ADAPTABILITY)
            monscore+=10 if (i.ability == PBAbilities::SYNCHRONIZE)
            monscore+=10 if (i.ability == PBAbilities::ANTICIPATION)
            monscore+=10 if (i.ability == PBAbilities::TELEPATHY)
          when 6
            monscore+=30 if (i.ability == PBAbilities::SHEERFORCE)
            monscore+=30 if (i.ability == PBAbilities::PUREPOWER)
            monscore+=30 if (i.ability == PBAbilities::HUGEPOWER)
            monscore+=30 if (i.ability == PBAbilities::GUTS)
            monscore+=10 if (i.ability == PBAbilities::DANCER)
            monscore+=20 if i.hasType?(:FIGHTING)
          when 7
            monscore+=25 if i.hasType?(:FIRE)
            monscore+=15 if (i.ability == PBAbilities::WATERVEIL)
            monscore+=15 if (i.ability == PBAbilities::WATERBUBBLE)
            monscore+=30 if (i.ability == PBAbilities::FLASHFIRE)
            monscore+=30 if (i.ability == PBAbilities::FLAREBOOST)
            monscore+=30 if (i.ability == PBAbilities::BLAZE)
            monscore-=30 if (i.ability == PBAbilities::ICEBODY)
            monscore-=30 if (i.ability == PBAbilities::LEAFGUARD)
            monscore-=30 if (i.ability == PBAbilities::GRASSPELT)
            monscore-=30 if (i.ability == PBAbilities::FLUFFY)
          when 8
            monscore+=15 if (i.ability == PBAbilities::GOOEY)
            monscore+=20 if (i.ability == PBAbilities::WATERCOMPACTION)
          when 9
            monscore+=10 if (i.ability == PBAbilities::WONDERSKIN)
            monscore+=20 if (i.ability == PBAbilities::MARVELSCALE)
            monscore+=25 if (i.ability == PBAbilities::SOULHEART)
            monscore+=30 if (i.ability == PBAbilities::CLOUDNINE)
            monscore+=30 if (i.ability == PBAbilities::PRISMARMOR)
          when 10
            monscore+=20 if (i.ability == PBAbilities::POISONHEAL)
            monscore+=25 if (i.ability == PBAbilities::TOXICBOOST)
            monscore+=30 if (i.ability == PBAbilities::MERCILESS)
            monscore+=30 if (i.ability == PBAbilities::CORROSION)
            monscore+=15 if i.hasType?(:POISON)
          when 11
            monscore+=10 if (i.ability == PBAbilities::WATERCOMPACTION)
            monscore+=20 if (i.ability == PBAbilities::POISONHEAL)
            monscore+=25 if (i.ability == PBAbilities::TOXICBOOST)
            monscore+=30 if (i.ability == PBAbilities::MERCILESS)
            monscore+=30 if (i.ability == PBAbilities::CORROSION)
            monscore+=15 if i.hasType?(:POISON)
          when 12
            monscore+=20 if ((i.ability == PBAbilities::SANDSTREAM) || (nonmegaform.ability == PBAbilities::SANDSTREAM))
            monscore+=25 if (i.ability == PBAbilities::SANDVEIL)
            monscore+=30 if (i.ability == PBAbilities::SANDFORCE)
            monscore+=50 if (i.ability == PBAbilities::SANDRUSH)
            monscore+=20 if i.hasType?(:GROUND)
            monscore-=25 if i.hasType?(:ELECTRIC)
          when 13
            monscore+=25 if i.hasType?(:ICE)
            monscore+=25 if (i.ability == PBAbilities::ICEBODY)
            monscore+=25 if (i.ability == PBAbilities::SNOWCLOAK)
            monscore+=25 if (i.ability == PBAbilities::REFRIGERATE)
            monscore+=50 if (i.ability == PBAbilities::SLUSHRUSH)
          when 14
          when 15
            monscore+=20 if (i.ability == PBAbilities::SAPSIPPER)
            monscore+=25 if i.hasType?(:GRASS) || i.hasType?(:BUG)
            monscore+=30 if (i.ability == PBAbilities::GRASSPELT)
            monscore+=30 if (i.ability == PBAbilities::OVERGROW)
            monscore+=30 if (i.ability == PBAbilities::SWARM)
          when 16
            monscore+=15 if i.hasType?(:FIRE)
          when 17
            monscore+=25 if i.hasType?(:ELECTRIC)
            monscore+=20 if (i.ability == PBAbilities::MOTORDRIVE)
            monscore+=20 if (i.ability == PBAbilities::STEELWORKER)
            monscore+=25 if (i.ability == PBAbilities::DOWNLOAD)
            monscore+=25 if (i.ability == PBAbilities::TECHNICIAN)
            monscore+=25 if (i.ability == PBAbilities::GALVANIZE)
          when 18
            monscore+=20 if (i.ability == PBAbilities::VOLTABSORB)
            monscore+=20 if (i.ability == PBAbilities::STATIC)
            monscore+=25 if (i.ability == PBAbilities::GALVANIZE)
            monscore+=50 if (i.ability == PBAbilities::SURGESURFER)
            monscore+=25 if i.hasType?(:ELECTRIC)
          when 19
            monscore+=10 if i.hasType?(:POISON)
            monscore+=10 if (i.ability == PBAbilities::CORROSION)
            monscore+=20 if (i.ability == PBAbilities::POISONHEAL)
            monscore+=20 if (i.ability == PBAbilities::EFFECTSPORE)
            monscore+=20 if (i.ability == PBAbilities::POISONPOINT)
            monscore+=20 if (i.ability == PBAbilities::STENCH)
            monscore+=20 if (i.ability == PBAbilities::GOOEY)
            monscore+=25 if (i.ability == PBAbilities::TOXICBOOST)
            monscore+=30 if (i.ability == PBAbilities::MERCILESS)
          when 20
            monscore+=10 if i.hasType?(:FIGHTING)
            monscore+=15 if (i.ability == PBAbilities::OWNTEMPO)
            monscore+=15 if (i.ability == PBAbilities::PUREPOWER)
            monscore+=15 if (i.ability == PBAbilities::STEADFAST)
            monscore+=20 if ((i.ability == PBAbilities::SANDSTREAM) || (nonmegaform.ability == PBAbilities::SANDSTREAM))
            monscore+=20 if (i.ability == PBAbilities::WATERCOMPACTION)
            monscore+=30 if (i.ability == PBAbilities::SANDFORCE)
            monscore+=35 if (i.ability == PBAbilities::SANDVEIL)
            monscore+=50 if (i.ability == PBAbilities::SANDRUSH)
          when 21
            monscore+=25 if i.hasType?(:WATER)
            monscore+=25 if i.hasType?(:ELECTRIC)
            monscore+=25 if (i.ability == PBAbilities::WATERVEIL)
            monscore+=25 if (i.ability == PBAbilities::HYDRATION)
            monscore+=25 if (i.ability == PBAbilities::TORRENT)
            monscore+=25 if (i.ability == PBAbilities::SCHOOLING)
            monscore+=25 if (i.ability == PBAbilities::WATERCOMPACTION)
            monscore+=50 if (i.ability == PBAbilities::SWIFTSWIM)
            monscore+=50 if (i.ability == PBAbilities::SURGESURFER)
            mod1=PBTypes.getEffectiveness(PBTypes::WATER,i.type1)
            mod2=(i.type1==i.type2) ? 2 : PBTypes.getEffectiveness(PBTypes::WATER,i.type2)
            monscore-=50 if mod1*mod2>4
          when 22
            monscore+=25 if i.hasType?(:WATER)
            monscore+=25 if i.hasType?(:ELECTRIC)
            monscore+=25 if (i.ability == PBAbilities::WATERVEIL)
            monscore+=25 if (i.ability == PBAbilities::HYDRATION)
            monscore+=25 if (i.ability == PBAbilities::TORRENT)
            monscore+=25 if (i.ability == PBAbilities::SCHOOLING)
            monscore+=25 if (i.ability == PBAbilities::WATERCOMPACTION)
            monscore+=50 if (i.ability == PBAbilities::SWIFTSWIM)
            monscore+=50 if (i.ability == PBAbilities::SURGESURFER)
            mod1=PBTypes.getEffectiveness(PBTypes::WATER,i.type1)
            mod2=(i.type1==i.type2) ? 2 : PBTypes.getEffectiveness(PBTypes::WATER,i.type2)
            monscore-=50 if mod1*mod2>4
          when 23
            monscore+=15 if i.hasType?(:GROUND)
          when 24
          when 25
            monscore+=25 if i.hasType?(:DRAGON)
            monscore+=30 if (i.ability == PBAbilities::PRISMARMOR)
          when 26
            monscore+=25 if i.hasType?(:WATER)
            monscore+=25 if i.hasType?(:POISON)
            monscore+=25 if i.hasType?(:ELECTRIC)
            monscore+=25 if (i.ability == PBAbilities::SCHOOLING)
            monscore+=25 if (i.ability == PBAbilities::WATERCOMPACTION)
            monscore+=25 if (i.ability == PBAbilities::TOXICBOOST)
            monscore+=25 if (i.ability == PBAbilities::POISONHEAL)
            monscore+=25 if (i.ability == PBAbilities::MERCILESS)
            monscore+=50 if (i.ability == PBAbilities::SWIFTSWIM)
            monscore+=50 if (i.ability == PBAbilities::SURGESURFER)
            monscore+=20 if (i.ability == PBAbilities::GOOEY)
            monscore+=20 if (i.ability == PBAbilities::STENCH)
          when 27
            monscore+=25 if i.hasType?(:ROCK)
            monscore+=25 if i.hasType?(:FLYING)
            monscore+=20 if ((i.ability == PBAbilities::SNOWWARNING) || (nonmegaform.ability == PBAbilities::SNOWWARNING))
            monscore+=20 if ((i.ability == PBAbilities::DROUGHT) || (nonmegaform.ability == PBAbilities::DROUGHT))
            monscore+=25 if (i.ability == PBAbilities::LONGREACH)
            monscore+=30 if (i.ability == PBAbilities::GALEWINGS) && @weather==PBWeather::STRONGWINDS
          when 28
            monscore+=25 if i.hasType?(:ROCK)
            monscore+=25 if i.hasType?(:FLYING)
            monscore+=25 if i.hasType?(:ICE)
            monscore+=20 if ((i.ability == PBAbilities::SNOWWARNING) || (nonmegaform.ability == PBAbilities::DROUGHT))
            monscore+=20 if ((i.ability == PBAbilities::DROUGHT) || (nonmegaform.ability == PBAbilities::DROUGHT))
            monscore+=20 if (i.ability == PBAbilities::ICEBODY)
            monscore+=20 if (i.ability == PBAbilities::SNOWCLOAK)
            monscore+=25 if (i.ability == PBAbilities::LONGREACH)
            monscore+=25 if (i.ability == PBAbilities::REFRIGERATE)
            monscore+=30 if (i.ability == PBAbilities::GALEWINGS) && @weather==PBWeather::STRONGWINDS
            monscore+=50 if (i.ability == PBAbilities::SLUSHRUSH)
          when 29
            monscore+=20 if i.hasType?(:NORMAL)
            monscore+=20 if (i.ability == PBAbilities::JUSTIFIED)
          when 30
            monscore+=25 if (i.ability == PBAbilities::SANDVEIL)
            monscore+=25 if (i.ability == PBAbilities::SNOWCLOAK)
            monscore+=25 if (i.ability == PBAbilities::ILLUSION)
            monscore+=25 if (i.ability == PBAbilities::TANGLEDFEET)
            monscore+=25 if (i.ability == PBAbilities::MAGICBOUNCE)
            monscore+=25 if (i.ability == PBAbilities::COLORCHANGE)
          when 31
            monscore+=25 if i.hasType?(:FAIRY)
            monscore+=25 if i.hasType?(:STEEL)
            monscore+=40 if i.hasType?(:DRAGON)
            monscore+=25 if (i.ability == PBAbilities::POWEROFALCHEMY)
            monscore+=25 if ((i.ability == PBAbilities::MAGICGUARD) || (nonmegaform.ability == PBAbilities::MAGICGUARD))
            monscore+=25 if (i.ability == PBAbilities::MAGICBOUNCE)
            monscore+=25 if (i.ability == PBAbilities::BATTLEARMOR)
            monscore+=25 if (i.ability == PBAbilities::SHELLARMOR)
            monscore+=25 if (i.ability == PBAbilities::MAGICIAN)
            monscore+=25 if (i.ability == PBAbilities::MARVELSCALE)
            monscore+=30 if (i.ability == PBAbilities::STANCECHANGE)
          when 32
            monscore+=25 if i.hasType?(:FIRE)
            monscore+=50 if i.hasType?(:DRAGON)
            monscore+=20 if (i.ability == PBAbilities::MARVELSCALE)
            monscore+=20 if (i.ability == PBAbilities::MULTISCALE)
            monscore+=20 if ((i.ability == PBAbilities::MAGMAARMOR) || (nonmegaform.ability == PBAbilities::MAGMAARMOR))
          when 33
            monscore+=25 if i.hasType?(:GRASS)
            monscore+=25 if i.hasType?(:BUG)
            monscore+=20 if (i.ability == PBAbilities::FLOWERGIFT)
            monscore+=20 if (i.ability == PBAbilities::FLOWERVEIL)
            monscore+=20 if ((i.ability == PBAbilities::DROUGHT) || (nonmegaform.ability == PBAbilities::DROUGHT))
            monscore+=20 if ((i.ability == PBAbilities::DRIZZLE) || (nonmegaform.ability == PBAbilities::DRIZZLE))
          when 34
            monscore+=25 if i.hasType?(:PSYCHIC)
            monscore+=25 if i.hasType?(:FAIRY)
            monscore+=25 if i.hasType?(:DARK)
            monscore+=20 if (i.ability == PBAbilities::MARVELSCALE)
            monscore+=20 if (i.ability == PBAbilities::VICTORYSTAR)
            monscore+=25 if ((i.ability == PBAbilities::ILLUMINATE) || (nonmegaform.ability == PBAbilities::ILLUMINATE))
            monscore+=30 if (i.ability == PBAbilities::SHADOWSHIELD)
          when 35
            monscore+=25 if i.hasType?(:FLYING)
            monscore+=25 if i.hasType?(:DARK)
            monscore+=20 if (i.ability == PBAbilities::VICTORYSTAR)
            monscore+=25 if (i.ability == PBAbilities::LEVITATE)
            monscore+=30 if (i.ability == PBAbilities::SHADOWSHIELD)
          when 36
          when 37
            monscore+=25 if i.hasType?(:PSYCHIC)
            monscore+=20 if (i.ability == PBAbilities::PUREPOWER)
            monscore+=20 if ((i.ability == PBAbilities::ANTICIPATION) || (nonmegaform.ability == PBAbilities::ANTICIPATION))
            monscore+=50 if (i.ability == PBAbilities::TELEPATHY)
        end
      end
      PBDebug.log(sprintf("Fields: %d",monscore)) if $INTERNAL
      if currentmon.pbOwnSide.effects[PBEffects::StealthRock] ||
        currentmon.pbOwnSide.effects[PBEffects::Spikes]>0
        monscore= (monscore*(i.hp.to_f/i.totalhp.to_f)).floor
      end
      hazpercent = totalHazardDamage(currentmon.pbOwnSide,nonmegaform.type1,nonmegaform.type2,nonmegaform.isAirborne?,skill)
      if hazpercent>(i.hp.to_f/i.totalhp)*100
        monscore=1
      end
      if theseRoles.include?(PBMonRoles::ACE) && skill>=PBTrainerAI.bestSkill
        monscore*= 0.3
      end
      monscore.floor
      PBDebug.log(sprintf("Score: %d",monscore)) if $INTERNAL
      PBDebug.log(sprintf(" ")) if $INTERNAL
      scorearray.push(monscore)
    end
    count=-1
    bestcount=-1
    highscore=-1000000000000
    for score in scorearray
      count+=1
      next if party[count].nil?
      if score>highscore
        highscore=score
        bestcount=count
      elsif score==highscore
        if party[count].hp>party[bestcount].hp
          bestcount=count
        end
      end
    end
    if !pbCanSwitchLax?(currentmon.index,bestcount,false)
      return -1
    else
      return bestcount
    end
  end

  def totalHazardDamage(side,type1,type2,airborne,skill)
    percentdamage = 0
    if side.effects[PBEffects::Spikes]>0 && (!airborne || @field.effects[PBEffects::Gravity]>0)
      spikesdiv=[8,8,6,4][side.effects[PBEffects::Spikes]]
      percentdamage += (100.0/spikesdiv).floor
    end
    if side.effects[PBEffects::StealthRock]
      supereff = -1
      atype=PBTypes::ROCK
      if skill>=PBTrainerAI.bestSkill
        if $fefieldeffect == 25
          atype1=PBTypes::WATER
          atype2=PBTypes::GRASS
          atype3=PBTypes::FIRE
          atype4=PBTypes::PSYCHIC
          eff1=PBTypes.getCombinedEffectiveness(atype1,type1,type2)
          eff2=PBTypes.getCombinedEffectiveness(atype2,type1,type2)
          eff3=PBTypes.getCombinedEffectiveness(atype3,type1,type2)
          eff4=PBTypes.getCombinedEffectiveness(atype4,type1,type2)
          supereff = [eff1,eff2,eff3,eff4].max
        end
      end
      eff=PBTypes.getCombinedEffectiveness(atype,type1,type2)
      eff = supereff if supereff > -1
      if eff>0
        if skill>=PBTrainerAI.bestSkill
          if $fefieldeffect == 14 || $fefieldeffect == 23
            eff = eff*2
          end
        end
        percentdamage += 100*(eff/32.0)
      end
    end
    return percentdamage
  end

################################################################################
# Choose an action.
################################################################################
  def pbDefaultChooseEnemyCommand(index)
    if !pbCanShowFightMenu?(index)
      return if pbEnemyShouldUseItem?(index)
      #return if pbEnemyShouldWithdraw?(index) Old Switching Method
      return if pbShouldSwitch?(index)
      pbAutoChooseMove(index)
      return
    else
      pbBuildMoveScores(index) #grab the array of scores/targets before doing anything else
      #print 1
      return if pbShouldSwitch?(index)
      #print 2
      #return if pbEnemyShouldWithdraw?(index) Old Switching Method
      return if pbEnemyShouldUseItem?(index)
      #print 3
      #return if pbAutoFightMenu(index)
      #print 4
      pbRegisterUltraBurst(index) if pbEnemyShouldUltraBurst?(index)
      pbRegisterMegaEvolution(index) if pbEnemyShouldMegaEvolve?(index)
      #print 5
      if pbEnemyShouldZMove?(index)
        return pbChooseEnemyZMove(index)
      end
      #print 6
      pbChooseMoves(index)
      #print 7
    end
  end

  def pbChooseEnemyZMove(index)  #Put specific cases for trainers using status Z-Moves
    chosenmove=false
    chosenindex=-1
    attacker = @battlers[index]
    opponent=attacker.pbOppositeOpposing
    otheropp=opponent.pbPartner
    skill=pbGetOwner(attacker.index).skill || 0
    for i in 0..3
      move=@battlers[index].moves[i]
      if @battlers[index].pbCompatibleZMoveFromMove?(move)
        if move.id == (PBMoves::CONVERSION) ||  move.id == (PBMoves::SPLASH)
          pbRegisterZMove(index)
          pbRegisterMove(index,i,false)
          pbRegisterTarget(index,opponent.index)
          return
        end
        if !chosenmove
          chosenindex = i
          chosenmove=move
        else
          if move.basedamage>chosenmove.basedamage
            chosenindex=i
            chosenmove=move
          end
        end
      end
    end
    
    #oppeff1 = chosenmove.pbTypeModifier(chosenmove.type,attacker,opponent)
    oppeff1 = pbTypeModNoMessages(chosenmove.type,attacker,opponent,chosenmove,skill)
    #oppeff2 = chosenmove.pbTypeModifier(chosenmove.type,attacker,otheropp)
    oppeff2 = pbTypeModNoMessages(chosenmove.type,attacker,otheropp,chosenmove,skill)
    oppeff1 = 0 if opponent.hp<(opponent.totalhp/2.0).round
    oppeff1 = 0 if (opponent.effects[PBEffects::Substitute]>0 || opponent.effects[PBEffects::Disguise]) && attacker.item!=(PBItems::KOMMONIUMZ2)
    oppeff2 = 0 if otheropp.hp<(otheropp.totalhp/2.0).round
    oppeff2 = 0 if (otheropp.effects[PBEffects::Substitute]>0 || otheropp.effects[PBEffects::Disguise]) && attacker.item!=(PBItems::KOMMONIUMZ2)
    oppmult=0
    for i in 1..7 #iterates through all the stats
      oppmult+=opponent.stages[i] if opponent.stages[i]>0
    end
    othermult=0
    for i in 1..7
      othermult+=otheropp.stages[i] if otheropp.stages[i]>0
    end
    if (oppeff1<4) && ((oppeff2<4) || otheropp.hp==0)
      pbChooseMoves(index)
    elsif oppeff1>oppeff2
      pbRegisterZMove(index)
      pbRegisterMove(index,chosenindex,false)
      pbRegisterTarget(index,opponent.index)
    elsif oppeff1<oppeff2
      pbRegisterZMove(index)
      pbRegisterMove(index,chosenindex,false)
      pbRegisterTarget(index,otheropp.index)
    elsif oppeff1==oppeff2
      if oppmult > othermult
        pbRegisterZMove(index)
        pbRegisterMove(index,chosenindex,false)
        pbRegisterTarget(index,opponent.index)
      elsif oppmult < othermult
        pbRegisterZMove(index)
        pbRegisterMove(index,chosenindex,false)
        pbRegisterTarget(index,otheropp.index)
      else
        if otheropp.hp > opponent.hp
          pbRegisterZMove(index)
          pbRegisterMove(index,chosenindex,false)
          pbRegisterTarget(index,otheropp.index)
        else
          pbRegisterZMove(index)
          pbRegisterMove(index,chosenindex,false)
          pbRegisterTarget(index,opponent.index)
        end
      end
    end
  end

################################################################################
# Other functions.
################################################################################
  def pbDbgPlayerOnly?(idx)
    return true if !$INTERNAL
    return pbOwnedByPlayer?(idx.index) if idx.respond_to?("index")
    return pbOwnedByPlayer?(idx)
  end

  def pbStdDev(scores)
    n=0
    sum=0
    scores.each{|s| sum+=s; n+=1 }
    return 0 if n==0
    mean=sum.to_f/n.to_f
    varianceTimesN=0
    for i in 0...scores.length
      if scores[i]>0
        deviation=scores[i].to_f-mean
        varianceTimesN+=deviation*deviation
      end
    end
    # Using population standard deviation
    # [(n-1) makes it a sample std dev, would be 0 with only 1 sample]
    return Math.sqrt(varianceTimesN/n)
  end
end