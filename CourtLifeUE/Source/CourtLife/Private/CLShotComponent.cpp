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
	ACLBallerCharacter* Owner = Cast<ACLBallerCharacter>(GetOwner());
	if (Owner && AnimSet)
	{
		if (const TObjectPtr<UAnimMontage>* Base = AnimSet->ShotBases.Find(Build.Jumpshot.Base))
		{
			// Upper-body releases are blended in the anim graph from Profile.ReleaseBlend.
			if (UAnimInstance* Anim = Owner->GetMesh()->GetAnimInstance()) Anim->Montage_Play(*Base, Profile.PlayRate);
		}
	}
	if (Owner) Owner->OnShotStarted();
	return true;
}

void UCLShotComponent::ReleaseShot()
{
	if (!bShooting || bReleased) return;
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
	// Never let a held button freeze the shot: auto-release (late) near the end.
	if (!bReleased && HeldMs >= Profile.DurationMs * 0.95f) ReleaseShot();
	if (HeldMs >= Profile.DurationMs) bShooting = false;
}

float UCLShotComponent::GetMeterFill() const
{
	return Profile.ReleaseTimeMs > 0 ? FMath::Clamp(HeldMs / (Profile.ReleaseTimeMs * 1.5f), 0.f, 1.f) : 0.f;
}

FVector2D UCLShotComponent::GetGreenBand() const
{
	const float Max = FMath::Max(1.f, Profile.ReleaseTimeMs * 1.5f);
	return FVector2D((Profile.ReleaseTimeMs - Profile.GreenWindowMs * 0.5f) / Max, (Profile.ReleaseTimeMs + Profile.GreenWindowMs * 0.5f) / Max);
}
