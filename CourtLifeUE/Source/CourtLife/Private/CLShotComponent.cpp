#include "CLShotComponent.h"

#include "Animation/AnimInstance.h"
#include "CLAssets.h"
#include "CLBasketball.h"
#include "CLBallerCharacter.h"
#include "CLCoreBridge.h"
#include "CLCourt.h"
#include "Components/SkeletalMeshComponent.h"
#include "CLShooting.h"

UCLShotComponent::UCLShotComponent()
{
	PrimaryComponentTick.bCanEverTick = true;
}

void UCLShotComponent::Configure(const FMyPlayerBuild& InBuild, UCLAnimSet* InAnimSet)
{
	Build = InBuild;
	AnimSet = InAnimSet;
	Profile = UCLBuildLibrary::ComputeShotProfile(Build);
}

bool UCLShotComponent::BeginShot()
{
	if (bShooting) return false;
	bShooting = true;
	bReleased = false;
	HeldMs = 0.f;
	ShotType = ECLShotType::Jumper;
	ACLBallerCharacter* Owner = Cast<ACLBallerCharacter>(GetOwner());

	// Close to the rim we finish instead of shooting. Read the approach speed
	// before OnShotStarted() stops the character.
	if (const ACLCourt* Court = Owner ? ACLCourt::Find(this) : nullptr)
	{
		const courtlife::Vec2 Spot = Court->CourtFromWorld(Owner->GetActorLocation());
		const double Dist = FMath::Sqrt(Spot.x * Spot.x + Spot.z * Spot.z);
		const double Speed = Owner->GetVelocity().Size2D() / CLUnitsPerFoot;
		ShotType = UCLBuildLibrary::ChooseFinish(Build, Dist, Speed);
		if (ShotType != ECLShotType::Jumper)
		{
			const courtlife::FinishType Type = CLBridge::ToCore(ShotType);
			FinishDistanceFt = Dist;
			FinishRating = courtlife::FinishRating(CLBridge::ToCore(Build.Attributes), Type, Dist);
			Finish = courtlife::ComputeFinishProfile(Type, {FinishRating, CLBridge::Rating(Build, courtlife::Attr::Vertical), Build.Body.HeightIn, Dist});
		}
	}

	if (Owner && AnimSet)
	{
		UAnimInstance* Anim = Owner->GetMesh()->GetAnimInstance();
		if (ShotType != ECLShotType::Jumper)
		{
			const FName Key = ShotType == ECLShotType::Dunk ? FName(TEXT("dunk")) : FName(TEXT("layup"));
			if (const TObjectPtr<UAnimMontage>* Montage = AnimSet->Finishes.Find(Key))
			{
				if (Anim) Anim->Montage_Play(*Montage);
			}
		}
		else if (const TObjectPtr<UAnimMontage>* Base = AnimSet->ShotBases.Find(Build.Jumpshot.Base))
		{
			// Upper-body releases are blended in the anim graph from Profile.ReleaseBlend.
			if (Anim) Anim->Montage_Play(*Base, Profile.PlayRate);
		}
	}
	if (Owner) Owner->OnShotStarted();
	return true;
}

void UCLShotComponent::ResolveFinish()
{
	bReleased = true;
	ACLBallerCharacter* Owner = Cast<ACLBallerCharacter>(GetOwner());
	if (!Owner) return;

	double DefDist = -1.0;
	if (const AActor* Def = Defender.Get())
	{
		DefDist = FVector::Dist2D(Def->GetActorLocation(), Owner->GetActorLocation()) / CLUnitsPerFoot;
	}
	const courtlife::FinishType Type = CLBridge::ToCore(ShotType);
	const double Contest = courtlife::ContestLevel(DefDist, DefenderHeightIn, Finish.contestResist);
	const double Chance = courtlife::FinishMakeProbability(Type, FinishRating, Contest, FinishDistanceFt);

	FCLShotResult Result;
	Result.ShotType = ShotType;
	Result.Contest = Contest;
	Result.MakeChance = Chance;
	Result.DistanceFt = FinishDistanceFt;
	Result.bMade = FMath::FRand() < Chance;
	Result.bBlocked = courtlife::IsBlocked(Result.bMade, Contest);

	if (ACLBasketball* Ball = Owner->GetBall())
	{
		if (Result.bBlocked)
		{
			// Swatted away from the rim, back toward the floor.
			FVector Away = Owner->GetActorForwardVector() * -1.0;
			Away.Z = 0;
			Ball->Deflect((Away.GetSafeNormal() * 14.0 + FVector(0, 0, 4.0)) * CLUnitsPerFoot);
		}
		else
		{
			Ball->Shoot(Result.bMade, 2, FinishDistanceFt, ShotType == ECLShotType::Dunk ? 0.14f : 0.45f);
		}
	}
	OnShotReleased.Broadcast(Result);
}

void UCLShotComponent::ReleaseShot()
{
	// Finishes resolve on their own timing; letting go of the button does nothing.
	if (!bShooting || bReleased || ShotType != ECLShotType::Jumper) return;
	bReleased = true;
	ACLBallerCharacter* Owner = Cast<ACLBallerCharacter>(GetOwner());
	ACLCourt* Court = ACLCourt::Find(this);
	if (!Owner || !Court) return;

	const FVector Pos = Owner->GetActorLocation();
	const courtlife::Vec2 Spot = Court->CourtFromWorld(Pos);
	const double Dist = FMath::Sqrt(Spot.x * Spot.x + Spot.z * Spot.z);
	const bool bThree = courtlife::IsThree(Spot);

	double DefDist = -1.0;
	if (const AActor* Def = Defender.Get())
	{
		DefDist = FVector::Dist2D(Def->GetActorLocation(), Pos) / CLUnitsPerFoot;
	}

	courtlife::ShotProfile Core = courtlife::ComputeShotProfile(CLBridge::ToCore(Build.Jumpshot),
		{CLBridge::Rating(Build, courtlife::Attr::ThreePoint), CLBridge::Rating(Build, courtlife::Attr::Vertical), Build.Body.HeightIn});
	const courtlife::ReleaseResult Release = courtlife::GradeRelease(Core, HeldMs);
	const double Contest = courtlife::ContestLevel(DefDist, DefenderHeightIn, Core.contestResist);
	const int Rating = courtlife::ShotRating(CLBridge::ToCore(Build.Attributes), Dist, bThree);
	const double Chance = courtlife::MakeProbability(Release.grade, Rating, Dist, Contest);

	FCLShotResult Result;
	Result.Grade = CLBridge::FromCore(Release.grade);
	Result.TimingDeltaMs = Release.deltaMs;
	Result.Contest = Contest;
	Result.MakeChance = Chance;
	Result.DistanceFt = Dist;
	Result.bThree = bThree;
	Result.bMade = FMath::FRand() < Chance;

	if (ACLBasketball* Ball = Owner->GetBall())
	{
		Ball->Shoot(Result.bMade, bThree ? 3 : 2, Dist);
	}
	OnShotReleased.Broadcast(Result);
}

void UCLShotComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	if (!bShooting) return;
	HeldMs += DeltaTime * 1000.f;
	if (ShotType != ECLShotType::Jumper)
	{
		if (!bReleased && HeldMs >= Finish.releaseTimeMs) ResolveFinish();
		if (HeldMs >= Finish.durationMs) bShooting = false;
		return;
	}
	// Never let a held button freeze the shot: auto-release (late) near the end.
	if (!bReleased && HeldMs >= Profile.DurationMs * 0.95f) ReleaseShot();
	if (HeldMs >= Profile.DurationMs) bShooting = false;
}

float UCLShotComponent::GetMeterFill() const
{
	if (ShotType != ECLShotType::Jumper) return 0.f;
	return Profile.ReleaseTimeMs > 0 ? FMath::Clamp(HeldMs / (Profile.ReleaseTimeMs * 1.5f), 0.f, 1.f) : 0.f;
}

FVector2D UCLShotComponent::GetGreenBand() const
{
	const float Max = FMath::Max(1.f, Profile.ReleaseTimeMs * 1.5f);
	return FVector2D((Profile.ReleaseTimeMs - Profile.GreenWindowMs * 0.5f) / Max, (Profile.ReleaseTimeMs + Profile.GreenWindowMs * 0.5f) / Max);
}
