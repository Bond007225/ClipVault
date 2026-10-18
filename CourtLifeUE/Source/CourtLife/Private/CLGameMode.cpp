#include "CLGameMode.h"

#include "CLBallerCharacter.h"
#include "CLBasketball.h"
#include "CLCoreBridge.h"
#include "CLCourt.h"
#include "CLDefenderController.h"
#include "CLDribbleComponent.h"
#include "CLShotComponent.h"
#include "Kismet/GameplayStatics.h"

void ACLGameMode::StartPlay()
{
	Super::StartPlay();
	Player = Cast<ACLBallerCharacter>(UGameplayStatics::GetPlayerPawn(this, 0));
	if (!Player) return;
	Player->GetShot()->OnShotReleased.AddDynamic(this, &ACLGameMode::HandleShot);
	Player->GetDribble()->OnComboFinished.AddDynamic(this, &ACLGameMode::HandleCombo);
	if (ACLBasketball* Ball = Player->GetBall()) Ball->OnBasket.AddDynamic(this, &ACLGameMode::HandleBasket);
	SetDefenderEnabled(true);
}

void ACLGameMode::SetDefenderEnabled(bool bEnabled)
{
	if (!bEnabled)
	{
		if (Defender) Defender->Destroy();
		Defender = nullptr;
		if (Player) Player->GetShot()->Defender = nullptr;
		return;
	}
	const ACLCourt* Court = ACLCourt::Find(this);
	if (Defender || !DefenderClass || !Court || !Player) return;
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn;
	const FVector Spot = Court->WorldFromCourt({DefenderStart.X, DefenderStart.Y}, 3.5);
	Defender = GetWorld()->SpawnActor<APawn>(DefenderClass, Spot, FRotator::ZeroRotator, Params);
	if (!Defender) return;
	if (!Defender->GetController()) Defender->SpawnDefaultController();
	if (ACLDefenderController* AI = Cast<ACLDefenderController>(Defender->GetController())) AI->SetHandler(Player);
	Player->GetShot()->Defender = Defender.Get();
}

void ACLGameMode::HandleShot(const FCLShotResult& Result)
{
	++Stats.FieldGoalsAttempted;
	if (Result.bThree) ++Stats.ThreesAttempted;
	if (Result.Grade == ECLReleaseGrade::Green) ++Stats.Greens;
	if (Defender)
	{
		if (ACLDefenderController* AI = Cast<ACLDefenderController>(Defender->GetController())) AI->ReactToShot();
	}
	OnShotFeedback.Broadcast(Result);
	OnStatsChanged.Broadcast(Stats);
}

void ACLGameMode::HandleBasket(int32 Points)
{
	Stats.Points += Points;
	++Stats.FieldGoalsMade;
	if (Points == 3) ++Stats.ThreesMade;
	OnStatsChanged.Broadcast(Stats);
}

void ACLGameMode::HandleCombo(const FString& ComboName, float Effectiveness)
{
	if (!Defender || !Player) return;
	ACLDefenderController* AI = Cast<ACLDefenderController>(Defender->GetController());
	if (!AI) return;
	const bool bWasUp = !AI->IsStumbling();
	AI->ReactToCombo(Effectiveness, CLBridge::Rating(Player->GetBuild(), courtlife::Attr::BallHandle));
	if (bWasUp && AI->IsStumbling())
	{
		++Stats.AnklesBroken;
		OnStatsChanged.Broadcast(Stats);
	}
}
